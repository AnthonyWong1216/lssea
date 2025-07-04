# LSSea - VIOS Shared Ethernet Adapter Analysis Tool

Enhanced VIOS script for displaying detailed information about Shared Ethernet Adapters with improved timeout handling and error recovery.

## Version 4.0 Enhancements

### Key Improvements:
- **Timeout Handling**: Commands like `fcstat` now timeout after 5 seconds and skip to next device
- **Enhanced Error Recovery**: Better error handling and logging
- **Performance Monitoring**: Added system performance metrics
- **Improved Logging**: Comprehensive logging to `/tmp/lsseaV4.log`
- **Better Status Indicators**: Enhanced color coding and status reporting

### Timeout Settings:
- `fcstat`: 5 seconds
- `ioscli` commands: 10 seconds  
- `lscfg`: 8 seconds
- `entstat`: 15 seconds

## Usage

```bash
# Basic usage
./lsseasV4.sh

# With color output
./lsseasV4.sh -c

# With buffer details
./lsseasV4.sh -b

# With performance monitoring
./lsseasV4.sh -p

# Show version
./lsseasV4.sh -v

# Show help
./lsseasV4.sh -h
```

## Features

- **FC Adapter Analysis**: Timeout-protected FC adapter information gathering
- **NPIV Mapping**: Enhanced NPIV mapping with timeout handling
- **vSCSI Mapping**: Improved vSCSI mapping information
- **Virtual Ethernet**: Comprehensive virtual ethernet adapter analysis
- **Performance Monitoring**: CPU, memory, and network statistics
- **Comprehensive Logging**: Detailed execution logs

## Requirements

- AIX Virtual I/O Server (VIOS)
- Root access
- Korn shell (ksh)

## Files

- `lsseasV3.sh`: Original version
- `lsseasV4.sh`: Enhanced version with timeout handling
- `README.md`: This documentation

## Author

AnthonyWong1216 - Enhanced from original lsseaV3 script

## License

MIT License 