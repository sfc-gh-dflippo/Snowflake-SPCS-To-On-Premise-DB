# Documentation Images

This directory contains all screenshots and diagrams used in the documentation.

## Image Inventory

All images were extracted from the original DOCX document and are referenced in the markdown files with descriptive filenames for clarity.

### AWS Implementation Images (10 total)

Located in: `docs/03_aws_implementation.md`

1. **nlb-listener-configuration.png** (1448x744)
   - Network Load Balancer Listener Configuration

2. **nlb-availability-zone-selection.png** (2048x763)
   - Network Load Balancer Availability Zone Selection

3. **nlb-target-group-attachment.png** (2048x631)
   - Network Load Balancer Target Group Attachment

4. **target-group-health-check-status.png** (2048x427)
   - Target Group Health Check Status

5. **nlb-security-configuration.png** (2048x684)
   - Network Load Balancer Security Configuration

6. **vpc-endpoint-service-configuration.png** (1757x511)
   - VPC Endpoint Service Configuration

7. **snowflake-privatelink-query-results.png** (681x397)
   - Snowflake PrivateLink Configuration Query Results

8. **vpc-endpoint-allow-principals.png** (1241x818)
   - AWS VPC Endpoint Service Allow Principals Configuration

9. **openflow-eai-assignment-ui.png** (2048x784)
   - Openflow External Access Integration Assignment UI

10. **openflow-runtime-configuration.png** (2048x622)
    - Openflow Runtime Configuration with External Access Integration

## Naming Convention

Images use descriptive kebab-case filenames that clearly indicate their content:
- `nlb-*` - Network Load Balancer related screenshots
- `vpc-*` - VPC and networking configuration screenshots
- `target-group-*` - Target Group configuration screenshots
- `snowflake-*` - Snowflake-specific configuration screenshots
- `openflow-*` - Openflow UI and configuration screenshots

## Image Format

- **Format**: PNG
- **Source**: Extracted from DOCX using python-docx library
- **Usage**: All images are properly embedded in markdown with descriptive alt text

## Markdown Embedding Format

Images are embedded using standard markdown syntax:

```markdown
![Descriptive Alt Text](images/descriptive-filename.png)
```

The combination of descriptive filenames and alt text makes the documentation more maintainable and accessible.

---

**Last Updated**: November 2025
