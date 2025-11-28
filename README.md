# SQL Server Engineering Portfolio

Professional SQL Server and Azure Database Engineering portfolio demonstrating high availability design, performance tuning, automation scripts, ETL workflows, and cloud operations.

## 📁 Repository Structure

```
sql-server-portfolio/
├── performance-tuning/          # SQL performance analysis scripts
├── high-availability/           # HA health check scripts
├── automation/                  # PowerShell automation tasks
├── etl-pipelines/              # ETL pipeline templates
├── monitoring-dashboards/       # Monitoring dashboard queries
└── python-tools/               # Python utilities for career development
```

## 🚀 Performance Tuning

Scripts for analyzing and optimizing SQL Server performance.

| File | Description |
|------|-------------|
| `index-analysis.sql` | Missing index recommendations, unused index identification, fragmentation analysis |
| `query-store-analysis.sql` | Top resource-consuming queries, plan regression detection, plan instability analysis |
| `wait-statistics.sql` | Wait stats summary, real-time blocking analysis, per-session waits |

**Key Features:**
- Automated CREATE INDEX statement generation
- Query Store performance insights
- Wait type categorization with recommendations

## 🔄 High Availability

Health checks for high availability configurations.

| File | Description |
|------|-------------|
| `alwayson-health-check.sql` | AG status, replica health, synchronization monitoring, listener config |
| `log-shipping-monitor.sql` | Primary/secondary status, job history, threshold alerts |
| `mirroring-status.sql` | Mirroring session status, endpoint configuration (deprecated feature) |
| `backup-validation.sql` | Backup compliance, missing backup alerts, backup trends |

**Key Features:**
- Synchronization lag detection
- Cluster health monitoring
- Backup compliance reporting

## ⚙️ Automation

PowerShell scripts for database automation and maintenance.

| File | Description |
|------|-------------|
| `Index-Maintenance.ps1` | Intelligent index maintenance based on fragmentation levels |
| `Backup-Database.ps1` | Full/differential/log backups with compression and retention |
| `Server-HealthCheck.ps1` | Comprehensive health monitoring with HTML/JSON reporting |

**Key Features:**
- Configurable fragmentation thresholds
- Automated backup retention management
- Multi-format health reports (Console/HTML/JSON)

## 📊 ETL Pipelines

Data warehouse ETL templates and data quality framework.

| File | Description |
|------|-------------|
| `customer-dimension-load.sql` | SCD Type 2 dimension loading with hash-based change detection |
| `sales-fact-load.sql` | Incremental fact table loading with validation |
| `data-quality-framework.sql` | Configurable data quality rules and profiling |

**Key Features:**
- Slowly Changing Dimension Type 2 implementation
- Batch control and error logging
- Comprehensive data quality rules engine

## 📈 Monitoring Dashboards

SQL queries for real-time monitoring and alerting.

| File | Description |
|------|-------------|
| `performance-metrics.sql` | CPU, memory, I/O, sessions, wait types, connections |
| `instance-health.sql` | Server config, uptime, jobs, backups, security audit |
| `alerting-thresholds.sql` | Configurable alert system with history tracking |

**Key Features:**
- Real-time performance metrics
- Configurable alert thresholds
- Integration-ready for Grafana/Power BI

## 🐍 Python Tools

Python utilities for SQL Server career development.

| File | Description |
|------|-------------|
| `keyword_extractor.py` | Extract technical keywords from job descriptions |
| `resume_tailor.py` | Customize resume content based on job requirements |

**Key Features:**
- Categorized skill extraction (databases, SQL, HA, cloud, etc.)
- Match score calculation
- Tailored bullet point suggestions
- Professional summary generation

## 🛠️ Requirements

### SQL Scripts
- SQL Server 2016 or later
- VIEW SERVER STATE permission
- Appropriate database permissions

### PowerShell Scripts
- PowerShell 5.1 or later
- SqlServer PowerShell module
- SQL Server administrative permissions

### Python Tools
- Python 3.6 or later
- No external dependencies (standard library only)

## 📖 Usage Examples

### Run Performance Analysis
```sql
USE [YourDatabase];
GO
:r "performance-tuning/index-analysis.sql"
```

### Execute Backup Automation
```powershell
.\automation\Backup-Database.ps1 -ServerInstance "localhost" -DatabaseName "ALL" -BackupType "Full" -BackupPath "D:\Backups"
```

### Check Server Health
```powershell
.\automation\Server-HealthCheck.ps1 -ServerInstance "localhost" -OutputFormat "HTML" -OutputPath ".\report.html"
```

### Analyze Job Description
```python
from keyword_extractor import analyze_job_description
analysis = analyze_job_description(job_text)
print(analysis['keywords_by_category'])
```

## 📜 License

MIT License - See [LICENSE](LICENSE) for details.

## 👤 Author

SQL Server Database Engineering Portfolio

---

*This portfolio demonstrates enterprise-level SQL Server database administration, performance tuning, automation, and data engineering skills.*
