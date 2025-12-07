# Machine Learning Integration

**Last Updated:** December 7, 2025  
**Difficulty:** Advanced

## Overview

This guide demonstrates how to integrate TimescaleDB with machine learning workflows for predictive maintenance, failure prediction, and process optimization in Ignition SCADA systems.

---

## ML Use Cases for SCADA Systems

### 1. Predictive Maintenance
- **Goal:** Predict equipment failures before they occur
- **Data:** Vibration, temperature, pressure, runtime hours
- **Algorithms:** Random Forest, LSTM, Isolation Forest

### 2. Anomaly Detection
- **Goal:** Identify abnormal process conditions
- **Data:** Process variables, setpoints, quality metrics
- **Algorithms:** Autoencoders, One-class SVM, Statistical methods

### 3. Process Optimization
- **Goal:** Optimize process parameters for efficiency
- **Data:** Input variables, output quality, energy consumption
- **Algorithms:** Linear regression, XGBoost, Neural networks

### 4. Quality Prediction
- **Goal:** Predict product quality from process data
- **Data:** Process parameters, sensor readings, lab results
- **Algorithms:** Gradient boosting, Random Forest

---

## Architecture

```
┌─────────────────┐
│  Ignition SCADA │
│   Tag Historian │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   TimescaleDB   │
│   Hypertables   │
│   + Continuous  │
│    Aggregates   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Python/Jython  │
│  ML Pipeline    │
│  - Extract      │
│  - Transform    │
│  - Train        │
│  - Predict      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Predictions    │
│  Written Back   │
│  to Tags        │
└─────────────────┘
```

---

## Part 1: Feature Engineering with TimescaleDB

### Create Feature Extraction View

```sql
-- ML-ready feature view
CREATE OR REPLACE VIEW ml_features AS
SELECT
    t.tagpath,
    d.t_stamp,
    to_timestamp(d.t_stamp / 1000) as timestamp,
    COALESCE(d.intvalue, d.floatvalue) as value,
    
    -- Time-based features
    EXTRACT(HOUR FROM to_timestamp(d.t_stamp / 1000)) as hour,
    EXTRACT(DOW FROM to_timestamp(d.t_stamp / 1000)) as day_of_week,
    EXTRACT(MONTH FROM to_timestamp(d.t_stamp / 1000)) as month,
    EXTRACT(QUARTER FROM to_timestamp(d.t_stamp / 1000)) as quarter,
    
    -- Lag features (previous values)
    LAG(COALESCE(d.intvalue, d.floatvalue), 1) OVER w as lag_1,
    LAG(COALESCE(d.intvalue, d.floatvalue), 2) OVER w as lag_2,
    LAG(COALESCE(d.intvalue, d.floatvalue), 3) OVER w as lag_3,
    
    -- Lead features (future values - for supervised learning)
    LEAD(COALESCE(d.intvalue, d.floatvalue), 1) OVER w as lead_1,
    
    -- Rolling statistics
    AVG(COALESCE(d.intvalue, d.floatvalue)) OVER (
        PARTITION BY d.tagid 
        ORDER BY d.t_stamp 
        ROWS BETWEEN 10 PRECEDING AND CURRENT ROW
    ) as rolling_avg_10,
    
    STDDEV(COALESCE(d.intvalue, d.floatvalue)) OVER (
        PARTITION BY d.tagid 
        ORDER BY d.t_stamp 
        ROWS BETWEEN 10 PRECEDING AND CURRENT ROW
    ) as rolling_stddev_10,
    
    -- Rate of change
    (COALESCE(d.intvalue, d.floatvalue) - 
     LAG(COALESCE(d.intvalue, d.floatvalue), 1) OVER w) as delta_1
    
FROM sqlth_1_data d
JOIN sqlth_te t ON d.tagid = t.id
WHERE d.dataintegrity = 192  -- Good quality only
WINDOW w AS (PARTITION BY d.tagid ORDER BY d.t_stamp);
```

### Statistical Aggregates for ML

```sql
-- Create continuous aggregate with statistical features
CREATE MATERIALIZED VIEW ml_stats_hourly
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', t_stamp) AS bucket,
    tagid,
    
    -- Central tendency
    AVG(COALESCE(intvalue, floatvalue)) AS mean,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY COALESCE(intvalue, floatvalue)) AS median,
    
    -- Dispersion
    STDDEV(COALESCE(intvalue, floatvalue)) AS stddev,
    VARIANCE(COALESCE(intvalue, floatvalue)) AS variance,
    
    -- Range
    MIN(COALESCE(intvalue, floatvalue)) AS min_val,
    MAX(COALESCE(intvalue, floatvalue)) AS max_val,
    MAX(COALESCE(intvalue, floatvalue)) - MIN(COALESCE(intvalue, floatvalue)) AS range_val,
    
    -- Quartiles
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY COALESCE(intvalue, floatvalue)) AS q1,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY COALESCE(intvalue, floatvalue)) AS q3,
    
    -- Count and quality
    COUNT(*) AS sample_count,
    COUNT(*) FILTER (WHERE dataintegrity = 192) AS good_count
    
FROM sqlth_1_data
GROUP BY bucket, tagid;

-- Add refresh policy
SELECT add_continuous_aggregate_policy('ml_stats_hourly',
    start_offset => INTERVAL '3 days',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');
```

---

## Part 2: Python Integration

### Setup Python Environment

```bash
# Create virtual environment
python3 -m venv ~/ml_env
source ~/ml_env/bin/activate

# Install required packages
pip install psycopg2-binary pandas numpy scikit-learn sqlalchemy
```

### Connect to TimescaleDB from Python

```python
# ml_connector.py
import psycopg2
import pandas as pd
from sqlalchemy import create_engine

class TimescaleDBConnector:
    """Connect to TimescaleDB and extract data for ML"""
    
    def __init__(self, host='localhost', database='historian', 
                 user='ignition', password='password'):
        self.connection_string = f'postgresql://{user}:{password}@{host}:5432/{database}'
        self.engine = create_engine(self.connection_string)
    
    def get_tag_history(self, tag_path, start_time, end_time):
        """Extract tag history as pandas DataFrame"""
        query = """
        SELECT 
            to_timestamp(d.t_stamp / 1000) as timestamp,
            COALESCE(d.intvalue, d.floatvalue) as value,
            d.dataintegrity as quality
        FROM sqlth_1_data d
        JOIN sqlth_te t ON d.tagid = t.id
        WHERE t.tagpath = %s
          AND d.t_stamp >= EXTRACT(EPOCH FROM %s::timestamp) * 1000
          AND d.t_stamp <= EXTRACT(EPOCH FROM %s::timestamp) * 1000
          AND d.dataintegrity = 192
        ORDER BY d.t_stamp;
        """
        return pd.read_sql(query, self.engine, 
                          params=(tag_path, start_time, end_time),
                          parse_dates=['timestamp'],
                          index_col='timestamp')
    
    def get_multiple_tags(self, tag_paths, start_time, end_time):
        """Get multiple tags and pivot to wide format"""
        query = """
        SELECT 
            to_timestamp(d.t_stamp / 1000) as timestamp,
            t.tagpath,
            COALESCE(d.intvalue, d.floatvalue) as value
        FROM sqlth_1_data d
        JOIN sqlth_te t ON d.tagid = t.id
        WHERE t.tagpath = ANY(%s)
          AND d.t_stamp >= EXTRACT(EPOCH FROM %s::timestamp) * 1000
          AND d.t_stamp <= EXTRACT(EPOCH FROM %s::timestamp) * 1000
          AND d.dataintegrity = 192
        ORDER BY d.t_stamp;
        """
        df = pd.read_sql(query, self.engine, 
                        params=(tag_paths, start_time, end_time),
                        parse_dates=['timestamp'])
        
        # Pivot to wide format (one column per tag)
        return df.pivot(index='timestamp', columns='tagpath', values='value')
    
    def get_aggregated_features(self, start_time, end_time):
        """Get pre-computed features from continuous aggregate"""
        query = """
        SELECT 
            to_timestamp(bucket / 1000) as timestamp,
            t.tagpath,
            mean, stddev, min_val, max_val,
            q1, median, q3, sample_count
        FROM ml_stats_hourly m
        JOIN sqlth_te t ON m.tagid = t.id
        WHERE bucket >= EXTRACT(EPOCH FROM %s::timestamp) * 1000
          AND bucket <= EXTRACT(EPOCH FROM %s::timestamp) * 1000
        ORDER BY bucket;
        """
        return pd.read_sql(query, self.engine, 
                          params=(start_time, end_time),
                          parse_dates=['timestamp'])
```

### Example: Extract Training Data

```python
# extract_training_data.py
from ml_connector import TimescaleDBConnector
import pandas as pd

# Connect to database
db = TimescaleDBConnector(
    host='192.168.1.100',
    database='historian',
    user='ignition',
    password='your_password'
)

# Define tag paths for features
feature_tags = [
    '[default]Production/Temperature',
    '[default]Production/Pressure',
    '[default]Production/FlowRate',
    '[default]Production/Vibration'
]

# Extract 1 year of data for training
df = db.get_multiple_tags(
    tag_paths=feature_tags,
    start_time='2024-01-01 00:00:00',
    end_time='2024-12-31 23:59:59'
)

# Handle missing values
df_filled = df.fillna(method='ffill').fillna(method='bfill')

# Resample to hourly (if needed)
df_hourly = df_filled.resample('1H').mean()

# Save for ML training
df_hourly.to_csv('training_data.csv')

print(f"Extracted {len(df_hourly)} hourly samples")
print(f"Features: {list(df_hourly.columns)}")
```

---

## Part 3: Predictive Maintenance Example

### Failure Prediction Model

```python
# predictive_maintenance.py
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report
from ml_connector import TimescaleDBConnector

# 1. Extract historical data
db = TimescaleDBConnector()

# Get features (process variables)
features = db.get_multiple_tags(
    tag_paths=[
        '[default]Motor/Temperature',
        '[default]Motor/Vibration',
        '[default]Motor/Current',
        '[default]Motor/Speed'
    ],
    start_time='2023-01-01',
    end_time='2024-12-31'
).fillna(method='ffill')

# Get failure events (from alarm history or manual log)
failures_query = """
SELECT 
    to_timestamp(eventtime) as timestamp,
    1 as failure
FROM alarm_events
WHERE source LIKE '%Motor%'
  AND priority >= 3  -- High/Critical only
  AND eventtype = 0  -- Active alarms
"""
failures = pd.read_sql(failures_query, db.engine, 
                       parse_dates=['timestamp'],
                       index_col='timestamp')

# 2. Create labels (failure within next 24 hours)
features['failure_24h'] = 0

for failure_time in failures.index:
    mask = (features.index >= failure_time - pd.Timedelta(hours=24)) & \
           (features.index < failure_time)
    features.loc[mask, 'failure_24h'] = 1

# 3. Feature engineering
features['temp_vibration_ratio'] = features['[default]Motor/Temperature'] / \
                                   (features['[default]Motor/Vibration'] + 1)

features['power'] = features['[default]Motor/Current'] * \
                    features['[default]Motor/Speed']

# Rolling statistics
for col in ['[default]Motor/Temperature', '[default]Motor/Vibration']:
    features[f'{col}_rolling_mean_6h'] = features[col].rolling(window=6).mean()
    features[f'{col}_rolling_std_6h'] = features[col].rolling(window=6).std()

# 4. Prepare training data
X = features.drop(['failure_24h'], axis=1).fillna(0)
y = features['failure_24h']

# Split data
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

# 5. Train model
model = RandomForestClassifier(
    n_estimators=100,
    max_depth=10,
    min_samples_split=20,
    class_weight='balanced',  # Handle imbalanced data
    random_state=42
)

model.fit(X_train, y_train)

# 6. Evaluate
y_pred = model.predict(X_test)
print(classification_report(y_test, y_pred))

# 7. Feature importance
feature_importance = pd.DataFrame({
    'feature': X.columns,
    'importance': model.feature_importances_
}).sort_values('importance', ascending=False)

print("\nTop 10 Most Important Features:")
print(feature_importance.head(10))

# 8. Save model
import joblib
joblib.dump(model, 'motor_failure_model.pkl')
```

### Deploy Predictions to Ignition

```python
# predict_and_write.py
import joblib
from ml_connector import TimescaleDBConnector
from java.util import Date

# Load trained model
model = joblib.load('motor_failure_model.pkl')

# Get latest data
db = TimescaleDBConnector()
current_features = db.get_multiple_tags(
    tag_paths=[
        '[default]Motor/Temperature',
        '[default]Motor/Vibration',
        '[default]Motor/Current',
        '[default]Motor/Speed'
    ],
    start_time='now() - INTERVAL 1 hour',
    end_time='now()'
).fillna(method='ffill')

# Engineer features (same as training)
current_features['temp_vibration_ratio'] = \
    current_features['[default]Motor/Temperature'] / \
    (current_features['[default]Motor/Vibration'] + 1)

current_features['power'] = \
    current_features['[default]Motor/Current'] * \
    current_features['[default]Motor/Speed']

# Predict failure probability
latest_data = current_features.iloc[-1:][model.feature_names_in_]
failure_probability = model.predict_proba(latest_data)[0][1]

# Write prediction back to Ignition tag
system.tag.writeBlocking(
    ['[default]ML/MotorFailureProbability'],
    [failure_probability]
)

# Trigger alarm if probability high
if failure_probability > 0.7:
    system.tag.writeBlocking(
        ['[default]ML/MotorFailureWarning'],
        [True]
    )
```

---

## Part 2: Time Series Forecasting

### LSTM Model for Process Prediction

```python
# lstm_forecasting.py
import pandas as pd
import numpy as np
from tensorflow import keras
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import LSTM, Dense, Dropout
from sklearn.preprocessing import MinMaxScaler

# 1. Load data
db = TimescaleDBConnector()

data = db.get_tag_history(
    tag_path='[default]Production/Temperature',
    start_time='2023-01-01',
    end_time='2024-12-31'
)

# 2. Preprocess
scaler = MinMaxScaler()
scaled_data = scaler.fit_transform(data[['value']])

# 3. Create sequences
def create_sequences(data, seq_length=24):
    X, y = [], []
    for i in range(len(data) - seq_length):
        X.append(data[i:i+seq_length])
        y.append(data[i+seq_length])
    return np.array(X), np.array(y)

SEQ_LENGTH = 24  # Use 24 hours to predict next hour
X, y = create_sequences(scaled_data, SEQ_LENGTH)

# Split
split = int(0.8 * len(X))
X_train, X_test = X[:split], X[split:]
y_train, y_test = y[:split], y[split:]

# 4. Build LSTM model
model = Sequential([
    LSTM(50, activation='relu', input_shape=(SEQ_LENGTH, 1), return_sequences=True),
    Dropout(0.2),
    LSTM(50, activation='relu'),
    Dropout(0.2),
    Dense(1)
])

model.compile(optimizer='adam', loss='mse', metrics=['mae'])

# 5. Train
history = model.fit(
    X_train, y_train,
    epochs=50,
    batch_size=32,
    validation_split=0.2,
    verbose=1
)

# 6. Evaluate
test_loss, test_mae = model.evaluate(X_test, y_test)
print(f'Test MAE: {test_mae}')

# 7. Make predictions
predictions = model.predict(X_test)
predictions_rescaled = scaler.inverse_transform(predictions)

# 8. Save model
model.save('temperature_forecast_model.h5')
```

---

## Part 3: Anomaly Detection

### Isolation Forest for Anomaly Detection

```python
# anomaly_detection.py
import pandas as pd
from sklearn.ensemble import IsolationForest
from ml_connector import TimescaleDBConnector

# 1. Extract features from continuous aggregate
db = TimescaleDBConnector()

query = """
SELECT 
    to_timestamp(bucket / 1000) as timestamp,
    t.tagpath,
    mean, stddev, min_val, max_val, range_val
FROM ml_stats_hourly m
JOIN sqlth_te t ON m.tagid = t.id
WHERE bucket >= EXTRACT(EPOCH FROM NOW() - INTERVAL '90 days') * 1000
  AND t.tagpath IN (
      '[default]Production/Temperature',
      '[default]Production/Pressure',
      '[default]Production/FlowRate'
  )
"""

df = pd.read_sql(query, db.engine, parse_dates=['timestamp'])

# Pivot to wide format
df_pivot = df.pivot_table(
    index='timestamp',
    columns='tagpath',
    values=['mean', 'stddev', 'range_val']
)

# Flatten column names
df_pivot.columns = ['_'.join(col).strip() for col in df_pivot.columns.values]
df_pivot = df_pivot.fillna(method='ffill')

# 2. Train Isolation Forest
iso_forest = IsolationForest(
    contamination=0.05,  # Expect 5% anomalies
    random_state=42,
    n_estimators=100
)

# Fit on normal operation data (exclude known issues)
normal_data = df_pivot[df_pivot.index < '2024-06-01']  # Before known incident
iso_forest.fit(normal_data)

# 3. Detect anomalies
anomaly_scores = iso_forest.decision_function(df_pivot)
anomaly_labels = iso_forest.predict(df_pivot)

# Add to dataframe
df_pivot['anomaly_score'] = anomaly_scores
df_pivot['is_anomaly'] = anomaly_labels == -1

# 4. Get anomalous periods
anomalies = df_pivot[df_pivot['is_anomaly']]
print(f"Found {len(anomalies)} anomalous hours out of {len(df_pivot)} ({len(anomalies)/len(df_pivot)*100:.2f}%)")

# 5. Save anomaly scores back to TimescaleDB
for idx, row in df_pivot.iterrows():
    timestamp_ms = int(idx.timestamp() * 1000)
    
    # Use Ignition scripting to write to tag
    # (This would run in Ignition Gateway/Designer script)
    """
    system.tag.writeBlocking(
        ['[default]ML/AnomalyScore'],
        [row['anomaly_score']]
    )
    """
```

---

## Part 4: Jython Integration (Ignition Gateway Scripts)

### Gateway Timer Script for Real-Time Predictions

```python
# Gateway Event Script: Timer (runs every 5 minutes)
import sys
sys.path.append('/path/to/ml_models/')

import joblib
import pandas as pd

# Load pre-trained model
model = joblib.load('/path/to/motor_failure_model.pkl')

# Get current features from tags
tag_paths = [
    '[default]Motor/Temperature',
    '[default]Motor/Vibration',
    '[default]Motor/Current',
    '[default]Motor/Speed'
]

# Read current values
values = system.tag.readBlocking(tag_paths)
current_data = {path: val.value for path, val in zip(tag_paths, values)}

# Create feature vector
features = pd.DataFrame([current_data])

# Engineer features (must match training)
features['temp_vibration_ratio'] = \
    features['[default]Motor/Temperature'] / \
    (features['[default]Motor/Vibration'] + 1)

features['power'] = \
    features['[default]Motor/Current'] * \
    features['[default]Motor/Speed']

# Make prediction
prediction = model.predict_proba(features)[0][1]

# Write to prediction tag
system.tag.writeBlocking(
    ['[default]ML/MotorFailureProbability'],
    [prediction]
)

# Log prediction
logger = system.util.getLogger('ML.Predictions')
logger.info(f'Motor failure probability: {prediction:.3f}')

# Trigger alarm if needed
if prediction > 0.7:
    system.tag.writeBlocking(
        ['[default]ML/HighFailureRisk'],
        [True]
    )
```

### Named Query for Feature Extraction

```sql
-- Named Query: getMLFeatures
-- Parameters: :startTime, :endTime, :tagPaths

WITH tag_ids AS (
    SELECT id, tagpath 
    FROM sqlth_te 
    WHERE tagpath = ANY(:tagPaths)
      AND retired IS NULL
)
SELECT 
    to_timestamp(d.t_stamp / 1000) as timestamp,
    t.tagpath,
    COALESCE(d.intvalue, d.floatvalue) as value,
    d.dataintegrity as quality,
    
    -- Statistical features over 1-hour window
    AVG(COALESCE(d.intvalue, d.floatvalue)) OVER (
        PARTITION BY d.tagid 
        ORDER BY d.t_stamp 
        RANGE BETWEEN 3600000 PRECEDING AND CURRENT ROW
    ) as rolling_mean_1h,
    
    STDDEV(COALESCE(d.intvalue, d.floatvalue)) OVER (
        PARTITION BY d.tagid 
        ORDER BY d.t_stamp 
        RANGE BETWEEN 3600000 PRECEDING AND CURRENT ROW
    ) as rolling_stddev_1h

FROM sqlth_1_data d
JOIN tag_ids t ON d.tagid = t.id
WHERE d.t_stamp >= EXTRACT(EPOCH FROM :startTime::timestamp) * 1000
  AND d.t_stamp <= EXTRACT(EPOCH FROM :endTime::timestamp) * 1000
  AND d.dataintegrity = 192
ORDER BY d.t_stamp, t.tagpath;
```

### Call Named Query from Script

```python
# Ignition script to get ML features
params = {
    'startTime': system.date.addHours(system.date.now(), -24),
    'endTime': system.date.now(),
    'tagPaths': ['[default]Motor/Temperature', '[default]Motor/Vibration']
}

# Execute named query
results = system.db.runNamedQuery('ML/getMLFeatures', params)

# Convert to dataset for processing
dataset = system.dataset.toPyDataSet(results)

# Process with ML model
# ... your ML code here
```

---

## Part 5: Scheduled ML Pipeline

### Gateway Scheduled Script

```python
# Gateway Event: Scheduled (Daily at 2 AM)
# Purpose: Retrain ML model with latest data

import sys
import subprocess

# 1. Trigger Python ML pipeline
python_script = '/opt/ml_pipelines/retrain_model.py'

try:
    # Run external Python script
    result = subprocess.call(['python3', python_script])
    
    if result == 0:
        logger = system.util.getLogger('ML.Training')
        logger.info('ML model retrained successfully')
        
        # Update last training timestamp
        system.tag.writeBlocking(
            ['[default]ML/LastTrainingTime'],
            [system.date.now()]
        )
    else:
        logger.error(f'ML training failed with code: {result}')
        
except Exception as e:
    logger = system.util.getLogger('ML.Training')
    logger.error(f'Error during ML training: {str(e)}')
```

---

## Best Practices

### Data Preparation
✅ **Filter for good quality data only** (`dataintegrity = 192`)  
✅ **Handle missing values appropriately**  
✅ **Resample to consistent intervals**  
✅ **Remove outliers carefully** (may be important events)  
✅ **Normalize/scale features**  

### Feature Engineering
✅ **Use continuous aggregates for pre-computed features**  
✅ **Create lag features for time dependencies**  
✅ **Include domain knowledge** (process understanding)  
✅ **Test feature importance**  

### Model Deployment
✅ **Version control ML models**  
✅ **Log predictions for monitoring**  
✅ **Set up alert thresholds**  
✅ **Implement feedback loop for retraining**  
✅ **Monitor model drift**  

---

## Troubleshooting

### Out of Memory in Python

```python
# Use chunked reading
chunksize = 100000
for chunk in pd.read_sql(query, db.engine, chunksize=chunksize):
    # Process chunk
    process_chunk(chunk)
```

### Slow Feature Extraction

```python
# Use continuous aggregates instead of raw data
df = db.get_aggregated_features(start_time, end_time)
# Much faster than computing statistics on raw data
```

### Model Drift

```python
# Monitor prediction distribution
recent_predictions = system.tag.queryTagHistory(
    paths=['[default]ML/MotorFailureProbability'],
    startDate=system.date.addDays(system.date.now(), -7),
    endDate=system.date.now()
)

# Check if predictions are in expected range
# Retrain if distribution shifts significantly
```

---

## Next Steps

- [Data Migration Guide](05-data-migration.md)
- [Continuous Aggregates](02-continuous-aggregates.md)
- [Python Scripting Examples](03-scripting-examples.md)

**Last Updated:** December 7, 2025
