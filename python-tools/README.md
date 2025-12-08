# Python Tools

Python utilities for SQL Server career development.

## Tools

### keyword_extractor.py
Extract technical keywords from job descriptions:
- Categorizes skills (databases, SQL skills, HA, cloud, etc.)
- Identifies experience requirements
- Calculates keyword frequency
- Provides comprehensive job analysis

**Usage:**
```python
from keyword_extractor import analyze_job_description, extract_keywords

# Analyze a job posting
analysis = analyze_job_description(job_text)
print(analysis['keywords_by_category'])
print(analysis['experience_requirements'])
```

### resume_tailor.py
Customize resume content for specific job postings:
- Matches resume skills to job requirements
- Calculates match score
- Suggests missing skills to add
- Generates tailored bullet points
- Creates customized professional summary
- Reorders skills by relevance

**Usage:**
```python
from resume_tailor import tailor_resume, generate_tailored_summary

# Create resume object and analyze
tailoring = tailor_resume(resume, job_description)
print(f"Match Score: {tailoring['match_score']}%")
print(f"Skills to add: {tailoring['skills_to_add']}")

# Generate tailored summary
summary = generate_tailored_summary(job_description, years_experience=5)
```

## Features

### Keyword Categories
- **Databases**: SQL Server, Azure SQL, MySQL, PostgreSQL, etc.
- **SQL Skills**: T-SQL, stored procedures, query optimization
- **High Availability**: Always On, failover clustering, DR
- **Performance**: Query Store, Extended Events, tuning
- **Cloud**: Azure, AWS, GCP, cloud services
- **ETL/BI**: SSIS, SSRS, Power BI, data warehouse
- **Automation**: PowerShell, Python, scripting
- **DevOps**: CI/CD, Git, containers
- **Security**: Encryption, compliance, auditing
- **Certifications**: Azure, AWS, Oracle certs

### Match Scoring
- Overall match percentage
- Category-by-category breakdown
- Skill gap analysis
- Actionable recommendations

## Installation

```bash
# No external dependencies required - uses Python standard library
python3 keyword_extractor.py
python3 resume_tailor.py
```

## Requirements

- Python 3.6 or later
- No external dependencies (uses standard library only)
