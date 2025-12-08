#!/usr/bin/env python3
"""
Resume Tailoring Tool
Purpose: Customize resume content based on job description keywords
Author: SQL Server Portfolio

This tool helps tailor resumes to specific job descriptions by:
- Matching resume skills to job requirements
- Suggesting improvements and additions
- Generating customized bullet points
"""

import re
import json
from typing import List, Dict, Optional
from keyword_extractor import extract_keywords, calculate_match_score


# Sample resume sections and skill mappings
SKILL_BULLET_TEMPLATES = {
    "sql_skills": [
        "Developed and optimized complex T-SQL stored procedures, reducing execution time by {improvement}%",
        "Created and maintained database views, functions, and triggers for business-critical applications",
        "Implemented query optimization strategies resulting in {improvement}% performance improvement",
        "Designed efficient indexing strategies using execution plan analysis"
    ],
    "high_availability": [
        "Configured and maintained Always On Availability Groups across {count} production servers",
        "Implemented disaster recovery solutions with RPO of {rpo} and RTO of {rto}",
        "Managed log shipping and database mirroring for high availability requirements",
        "Developed and tested failover procedures, achieving {uptime}% uptime SLA"
    ],
    "performance": [
        "Utilized Query Store and Extended Events for proactive performance monitoring",
        "Identified and resolved performance bottlenecks through wait statistics analysis",
        "Implemented memory-optimized tables and columnstore indexes for analytics workloads",
        "Reduced query execution time by {improvement}% through systematic tuning"
    ],
    "cloud": [
        "Migrated {count} on-premises databases to Azure SQL Database",
        "Managed Azure Synapse Analytics for enterprise data warehouse solutions",
        "Implemented hybrid connectivity between on-premises and Azure environments",
        "Optimized Azure SQL costs through elastic pools and reserved capacity"
    ],
    "etl_bi": [
        "Designed and implemented SSIS packages for data integration workflows",
        "Created Power BI dashboards and reports for business stakeholders",
        "Developed dimensional data models following star schema best practices",
        "Built automated data pipelines processing {volume} records daily"
    ],
    "automation": [
        "Automated database maintenance tasks using PowerShell and SQL Agent",
        "Developed Python scripts for database monitoring and alerting",
        "Created automated backup verification and restore testing procedures",
        "Implemented infrastructure as code for database deployments"
    ],
    "security": [
        "Implemented Transparent Data Encryption (TDE) for data at rest security",
        "Configured row-level security and dynamic data masking for compliance",
        "Conducted security audits and implemented remediation measures",
        "Ensured compliance with {regulation} requirements"
    ]
}


class ResumeSection:
    """Represents a section of a resume."""
    
    def __init__(self, title: str, content: List[str]):
        self.title = title
        self.content = content
    
    def to_dict(self) -> Dict:
        return {"title": self.title, "content": self.content}


class Resume:
    """Represents a resume with sections and skills."""
    
    def __init__(self):
        self.contact_info = {}
        self.summary = ""
        self.skills = []
        self.experience = []
        self.education = []
        self.certifications = []
    
    def extract_keywords(self) -> Dict[str, List[str]]:
        """Extract keywords from resume content."""
        full_text = self.summary + " " + " ".join(self.skills)
        for exp in self.experience:
            full_text += " " + " ".join(exp.content)
        return extract_keywords(full_text)
    
    def to_dict(self) -> Dict:
        return {
            "contact_info": self.contact_info,
            "summary": self.summary,
            "skills": self.skills,
            "experience": [e.to_dict() for e in self.experience],
            "education": [e.to_dict() for e in self.education],
            "certifications": self.certifications
        }


def generate_tailored_bullets(missing_skills: List[str], 
                              category: str) -> List[str]:
    """
    Generate tailored bullet points for missing skills.
    
    Args:
        missing_skills: Skills to address
        category: Skill category
        
    Returns:
        List of suggested bullet points
    """
    templates = SKILL_BULLET_TEMPLATES.get(category, [])
    suggestions = []
    
    for template in templates[:2]:  # Limit to 2 suggestions per category
        # Fill in placeholders with reasonable defaults
        bullet = template.format(
            improvement=50,
            count=10,
            rpo="15 minutes",
            rto="1 hour",
            uptime=99.9,
            volume="1M+",
            regulation="SOC2"
        )
        suggestions.append(bullet)
    
    return suggestions


def tailor_resume(resume: Resume, job_text: str) -> Dict:
    """
    Analyze and provide tailoring suggestions for a resume.
    
    Args:
        resume: Resume object to analyze
        job_text: Job description text
        
    Returns:
        Tailoring recommendations
    """
    job_keywords = extract_keywords(job_text)
    resume_keywords = resume.extract_keywords()
    
    match_analysis = calculate_match_score(job_keywords, resume_keywords)
    
    tailoring_suggestions = {
        "match_score": match_analysis["overall_score"],
        "skills_to_highlight": match_analysis["matched_skills"],
        "skills_to_add": match_analysis["missing_skills"],
        "summary_suggestions": [],
        "bullet_suggestions": [],
        "keyword_density": {}
    }
    
    # Generate summary suggestions
    if match_analysis["matched_skills"]:
        top_matches = match_analysis["matched_skills"][:5]
        tailoring_suggestions["summary_suggestions"].append(
            f"Emphasize these matching skills in your summary: {', '.join(top_matches)}"
        )
    
    # Generate bullet point suggestions for missing skills
    for category, data in match_analysis["category_scores"].items():
        if data.get("missing"):
            bullets = generate_tailored_bullets(data["missing"], category)
            if bullets:
                tailoring_suggestions["bullet_suggestions"].extend([
                    {"category": category, "bullet": b, "addresses": data["missing"]}
                    for b in bullets
                ])
    
    # Calculate keyword density recommendations
    for category, keywords in job_keywords.items():
        resume_count = len(resume_keywords.get(category, []))
        job_count = len(keywords)
        if job_count > 0:
            density = resume_count / job_count * 100
            tailoring_suggestions["keyword_density"][category] = {
                "current": resume_count,
                "required": job_count,
                "coverage": round(density, 1)
            }
    
    return tailoring_suggestions


def generate_tailored_summary(job_text: str, 
                              years_experience: int = 5,
                              current_title: str = "SQL Server DBA") -> str:
    """
    Generate a tailored professional summary based on job requirements.
    
    Args:
        job_text: Job description text
        years_experience: Years of experience
        current_title: Current job title
        
    Returns:
        Tailored professional summary
    """
    keywords = extract_keywords(job_text)
    
    # Build summary components
    primary_skills = []
    for category in ["databases", "sql_skills", "high_availability"]:
        if category in keywords:
            primary_skills.extend(keywords[category][:2])
    
    secondary_skills = []
    for category in ["cloud", "automation", "etl_bi"]:
        if category in keywords:
            secondary_skills.extend(keywords[category][:1])
    
    summary_parts = [
        f"Results-driven {current_title} with {years_experience}+ years of experience",
    ]
    
    if primary_skills:
        summary_parts.append(
            f"specializing in {', '.join(primary_skills[:3])}"
        )
    
    if secondary_skills:
        summary_parts.append(
            f"with additional expertise in {', '.join(secondary_skills)}"
        )
    
    summary_parts.append(
        "Proven track record of optimizing database performance, "
        "implementing high availability solutions, and driving operational excellence."
    )
    
    return " ".join(summary_parts)


def reorder_skills(resume_skills: List[str], 
                   job_keywords: Dict[str, List[str]]) -> List[str]:
    """
    Reorder resume skills to prioritize job-relevant skills.
    
    Args:
        resume_skills: Current list of resume skills
        job_keywords: Keywords from job description
        
    Returns:
        Reordered skills list
    """
    # Flatten job keywords
    priority_skills = set()
    for keywords in job_keywords.values():
        priority_skills.update([k.lower() for k in keywords])
    
    # Separate matching and non-matching skills
    matching = []
    non_matching = []
    
    for skill in resume_skills:
        if skill.lower() in priority_skills:
            matching.append(skill)
        else:
            non_matching.append(skill)
    
    return matching + non_matching


def main():
    """Demo the resume tailoring capabilities."""
    
    # Sample job description
    job_description = """
    Senior SQL Server Database Administrator
    
    Requirements:
    - 5+ years experience with SQL Server
    - Strong T-SQL and stored procedure development
    - Experience with Always On Availability Groups
    - Azure SQL Database experience
    - PowerShell automation skills
    - SSIS experience preferred
    """
    
    # Sample resume
    resume = Resume()
    resume.summary = "Experienced database administrator with SQL Server expertise"
    resume.skills = [
        "SQL Server", "T-SQL", "Stored Procedures", "MySQL",
        "Python", "PowerShell", "Performance Tuning"
    ]
    
    exp1 = ResumeSection(
        "Database Administrator - Company A",
        [
            "Managed SQL Server databases in production environment",
            "Developed stored procedures for business applications",
            "Implemented backup and recovery procedures"
        ]
    )
    resume.experience = [exp1]
    
    print("=" * 60)
    print("Resume Tailoring Analysis")
    print("=" * 60)
    
    tailoring = tailor_resume(resume, job_description)
    
    print(f"\nMatch Score: {tailoring['match_score']}%")
    
    print("\nSkills to Highlight:")
    print("-" * 40)
    for skill in tailoring["skills_to_highlight"]:
        print(f"  ✓ {skill}")
    
    print("\nSkills to Add:")
    print("-" * 40)
    for skill in tailoring["skills_to_add"]:
        print(f"  + {skill}")
    
    print("\nSuggested Bullet Points:")
    print("-" * 40)
    for suggestion in tailoring["bullet_suggestions"][:5]:
        print(f"\n  Category: {suggestion['category']}")
        print(f"  • {suggestion['bullet']}")
    
    print("\n\nTailored Summary:")
    print("-" * 40)
    print(generate_tailored_summary(job_description))
    
    print("\n\nReordered Skills (priority first):")
    print("-" * 40)
    job_keywords = extract_keywords(job_description)
    reordered = reorder_skills(resume.skills, job_keywords)
    print(", ".join(reordered))
    
    print("\n" + "=" * 60)
    print("JSON Output:")
    print("=" * 60)
    print(json.dumps(tailoring, indent=2))


if __name__ == "__main__":
    main()
