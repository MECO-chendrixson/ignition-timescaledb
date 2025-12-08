# Contributing to Ignition TimescaleDB Integration

**Version:** 1.3.0  
**Last Updated:** December 8, 2025  
**Maintained by:** Miller-Eads Automation

Thank you for your interest in contributing to this documentation project!

## How to Contribute

### Reporting Issues

If you encounter problems or have suggestions:

1. Check existing issues to avoid duplicates
2. Provide detailed information:
   - Ignition version
   - PostgreSQL version
   - TimescaleDB version
   - Operating system
   - Error messages or unexpected behavior
   - Steps to reproduce

### Documentation Improvements

To contribute documentation improvements:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improve-xyz`)
3. Make your changes
4. Test any SQL scripts or examples
5. Commit your changes (`git commit -am 'Improve XYZ documentation'`)
6. Push to the branch (`git push origin feature/improve-xyz`)
7. Create a Pull Request

### Adding Examples

When adding examples:

- Ensure they are tested and working
- Include comments explaining the purpose
- Follow the existing documentation style
- Add to the appropriate section
- Update the README if adding new sections

### SQL Scripts

For SQL contributions:

- Test scripts on a clean database
- Include comments and documentation
- Use consistent formatting
- Add error handling where appropriate
- Update version headers

## Documentation Style Guide

### Markdown Format

- Use clear, descriptive headers
- Include code blocks with proper syntax highlighting
- Use tables for comparison data
- Add links to related sections
- Include troubleshooting tips

### Example Structure

```markdown
# Title

**Overview:** Brief description

## Section 1

Content with examples:

\```sql
-- SQL example
SELECT * FROM table;
\```

### Subsection

More details...
```

### Code Style

- SQL: UPPERCASE for keywords, lowercase for identifiers
- Python: Follow PEP 8
- Shell: Use clear variable names, add comments

## Testing

Before submitting:

1. Verify all SQL scripts run without errors
2. Check markdown formatting renders correctly
3. Test any code examples
4. Ensure links are not broken

## Questions?

Feel free to open an issue for any questions about contributing.

## License

By contributing, you agree that your contributions will be part of this documentation project.

---

Thank you for helping improve this resource!
