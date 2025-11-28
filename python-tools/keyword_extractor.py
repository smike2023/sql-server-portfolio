#!/usr/bin/env python3
"""
Keyword Extractor for Job Descriptions
Purpose: Extract technical keywords and skills from job descriptions
Author: SQL Server Portfolio

This tool analyzes job descriptions to identify key technical skills,
technologies, and requirements for SQL Server and database engineering roles.
"""

import re
import json
from collections import Counter
from typing import List, Dict, Set, Tuple


# Technical keyword categories for SQL Server and database roles
SKILL_CATEGORIES = {
    "databases": [
        "sql server", "azure sql", "mysql", "postgresql", "oracle",
        "mongodb", "cosmos db", "dynamodb", "redis", "cassandra",
        "mariadb", "sqlite", "nosql", "rdbms", "database"
    ],
    "sql_skills": [
        "t-sql", "transact-sql", "stored procedures", "triggers",
        "functions", "views", "indexes", "query optimization",
        "execution plans", "query tuning", "cte", "window functions",
        "pivot", "unpivot", "merge", "bulk insert"
    ],
    "high_availability": [
        "always on", "availability groups", "failover clustering",
        "log shipping", "database mirroring", "replication",
        "disaster recovery", "backup", "restore", "rpo", "rto",
        "high availability", "ha", "dr"
    ],
    "performance": [
        "performance tuning", "query store", "extended events",
        "profiler", "wait statistics", "index tuning",
        "memory optimization", "in-memory oltp", "columnstore",
        "partitioning", "compression"
    ],
    "cloud": [
        "azure", "aws", "gcp", "cloud", "iaas", "paas", "saas",
        "azure synapse", "azure data factory", "aws rds",
        "elastic pool", "managed instance", "serverless"
    ],
    "etl_bi": [
        "ssis", "ssrs", "ssas", "power bi", "tableau",
        "etl", "data warehouse", "data lake", "olap", "oltp",
        "dimensional modeling", "star schema", "snowflake schema",
        "data pipeline", "data integration"
    ],
    "automation": [
        "powershell", "python", "automation", "scripting",
        "sql agent", "job scheduling", "maintenance plans",
        "dbatools", "terraform", "ansible"
    ],
    "devops": [
        "devops", "ci/cd", "git", "azure devops", "github actions",
        "jenkins", "docker", "kubernetes", "containers",
        "infrastructure as code", "iac"
    ],
    "security": [
        "security", "encryption", "tde", "always encrypted",
        "row-level security", "dynamic data masking",
        "audit", "compliance", "gdpr", "hipaa", "soc2"
    ],
    "certifications": [
        "mcsa", "mcse", "azure administrator", "azure solutions architect",
        "azure database administrator", "dp-300", "az-900", "az-104",
        "aws certified", "oci certified"
    ],
    "soft_skills": [
        "communication", "team player", "problem solving",
        "analytical", "documentation", "mentoring", "leadership",
        "collaboration", "agile", "scrum"
    ]
}


def extract_keywords(text: str) -> Dict[str, List[str]]:
    """
    Extract technical keywords from job description text.
    
    Args:
        text: Job description text
        
    Returns:
        Dictionary of categorized keywords found
    """
    text_lower = text.lower()
    found_keywords = {}
    
    for category, keywords in SKILL_CATEGORIES.items():
        matches = []
        for keyword in keywords:
            # Use word boundary matching for accurate detection
            pattern = r'\b' + re.escape(keyword) + r'\b'
            if re.search(pattern, text_lower):
                matches.append(keyword)
        
        if matches:
            found_keywords[category] = matches
    
    return found_keywords


def extract_years_experience(text: str) -> List[Tuple[str, int]]:
    """
    Extract years of experience requirements from text.
    
    Args:
        text: Job description text
        
    Returns:
        List of (skill/area, years) tuples
    """
    patterns = [
        r'(\d+)\+?\s*(?:years?|yrs?)(?:\s+of)?\s+(?:experience|exp)?\s*(?:with|in)?\s*([a-zA-Z\s]+)',
        r'(\d+)\+?\s*(?:years?|yrs?)\s+([a-zA-Z\s]+)\s+experience',
    ]
    
    results = []
    for pattern in patterns:
        matches = re.findall(pattern, text.lower())
        for match in matches:
            years = int(match[0])
            skill = match[1].strip()[:50]  # Limit skill text length
            if skill and years > 0 and years < 30:  # Sanity check
                results.append((skill, years))
    
    return results


def calculate_match_score(job_keywords: Dict[str, List[str]], 
                          resume_keywords: Dict[str, List[str]]) -> Dict:
    """
    Calculate match score between job requirements and resume.
    
    Args:
        job_keywords: Keywords extracted from job description
        resume_keywords: Keywords extracted from resume
        
    Returns:
        Match analysis with scores and recommendations
    """
    results = {
        "overall_score": 0,
        "category_scores": {},
        "matched_skills": [],
        "missing_skills": [],
        "recommendations": []
    }
    
    total_job_keywords = 0
    total_matches = 0
    
    for category, job_skills in job_keywords.items():
        resume_skills = resume_keywords.get(category, [])
        job_set = set(job_skills)
        resume_set = set(resume_skills)
        
        matches = job_set.intersection(resume_set)
        missing = job_set - resume_set
        
        total_job_keywords += len(job_set)
        total_matches += len(matches)
        
        if job_set:
            category_score = len(matches) / len(job_set) * 100
            results["category_scores"][category] = {
                "score": round(category_score, 1),
                "matched": list(matches),
                "missing": list(missing)
            }
        
        results["matched_skills"].extend(list(matches))
        results["missing_skills"].extend(list(missing))
    
    if total_job_keywords > 0:
        results["overall_score"] = round(total_matches / total_job_keywords * 100, 1)
    
    # Generate recommendations
    if results["overall_score"] < 50:
        results["recommendations"].append(
            "Consider gaining more skills in the required areas before applying"
        )
    elif results["overall_score"] < 70:
        results["recommendations"].append(
            "Good foundation, but highlight transferable skills in your resume"
        )
    else:
        results["recommendations"].append(
            "Strong match! Customize your resume to emphasize matching skills"
        )
    
    # Add specific recommendations for missing high-priority skills
    priority_categories = ["databases", "sql_skills", "high_availability"]
    for category in priority_categories:
        if category in results["category_scores"]:
            missing = results["category_scores"][category].get("missing", [])
            if missing:
                results["recommendations"].append(
                    f"Consider learning: {', '.join(missing[:3])}"
                )
    
    return results


def analyze_job_description(job_text: str) -> Dict:
    """
    Perform comprehensive analysis of a job description.
    
    Args:
        job_text: Full job description text
        
    Returns:
        Complete analysis including keywords, requirements, and insights
    """
    analysis = {
        "keywords_by_category": extract_keywords(job_text),
        "experience_requirements": extract_years_experience(job_text),
        "keyword_frequency": {},
        "summary": {}
    }
    
    # Count all technical terms
    all_keywords = []
    for keywords in analysis["keywords_by_category"].values():
        all_keywords.extend(keywords)
    
    analysis["keyword_frequency"] = dict(Counter(all_keywords).most_common(20))
    
    # Generate summary
    total_skills = len(all_keywords)
    categories_found = len(analysis["keywords_by_category"])
    
    analysis["summary"] = {
        "total_technical_skills": total_skills,
        "categories_covered": categories_found,
        "primary_focus": list(analysis["keywords_by_category"].keys())[:3],
        "experience_range": f"{min([e[1] for e in analysis['experience_requirements']], default=0)}-{max([e[1] for e in analysis['experience_requirements']], default=0)} years" if analysis['experience_requirements'] else "Not specified"
    }
    
    return analysis


def main():
    """Demo the keyword extraction capabilities."""
    
    sample_job_description = """
    Senior SQL Server Database Administrator
    
    We are looking for an experienced SQL Server DBA with 5+ years of experience
    in enterprise database administration. The ideal candidate will have strong
    skills in T-SQL, performance tuning, and high availability solutions.
    
    Requirements:
    - 5+ years experience with SQL Server 2016 or later
    - Strong T-SQL skills including stored procedures, functions, and triggers
    - Experience with Always On Availability Groups and failover clustering
    - Knowledge of query optimization and execution plans
    - Experience with Azure SQL Database and Azure Synapse
    - Familiarity with PowerShell scripting and automation
    - Experience with SSIS, SSRS, or other ETL tools
    - Understanding of backup and disaster recovery strategies
    
    Nice to have:
    - Azure certification (DP-300 or similar)
    - Experience with Python for automation
    - Knowledge of DevOps practices and CI/CD pipelines
    """
    
    print("=" * 60)
    print("Job Description Keyword Analysis")
    print("=" * 60)
    
    analysis = analyze_job_description(sample_job_description)
    
    print("\nKeywords by Category:")
    print("-" * 40)
    for category, keywords in analysis["keywords_by_category"].items():
        print(f"\n{category.upper()}:")
        print(f"  {', '.join(keywords)}")
    
    print("\n\nExperience Requirements:")
    print("-" * 40)
    for skill, years in analysis["experience_requirements"]:
        print(f"  {years}+ years: {skill}")
    
    print("\n\nSummary:")
    print("-" * 40)
    for key, value in analysis["summary"].items():
        print(f"  {key}: {value}")
    
    print("\n" + "=" * 60)
    print("JSON Output:")
    print("=" * 60)
    print(json.dumps(analysis, indent=2))


if __name__ == "__main__":
    main()
