# Lab Profiles

This folder contains example JSON templates for lab configuration profiles used by Exchange Lab Manager.

These files are intended as reusable starting points for defining a lab environment, including:

- static IP and gateway settings
- domain and forest names
- Exchange ISO and EOMT paths
- SMTP target details
- mailbox and user test parameters

## Files

- `template.json` - blank template for creating a new lab profile.
- `example-minimal-lab.json` - minimal required fields for a simple isolated lab.
- `example-standard-lab.json` - a more complete example with common configuration values.

## Usage

Use these templates as documentation for the fields expected by future profile-loading workflows. They are not currently consumed by the GUI automatically, but they provide a consistent JSON schema for future automation.
