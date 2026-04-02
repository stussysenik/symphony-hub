from __future__ import annotations

import re
from pathlib import Path

import yaml


CONFIG_HEADER = """# Symphony Multi-Project Configuration
# Location: /Users/s3nik/Desktop/symphony-hub/projects.yml
"""


def load_config(config_path: Path) -> dict:
    with config_path.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def save_config(config_path: Path, config: dict) -> None:
    body = yaml.safe_dump(config, sort_keys=False, allow_unicode=False, width=1000)
    config_path.write_text(f"{CONFIG_HEADER}\n{body}", encoding="utf-8")


def normalize_repo_slug(github_url: str) -> str:
    cleaned = (github_url or "").strip()
    cleaned = re.sub(r"\.git$", "", cleaned)
    cleaned = re.sub(r"^https://github\.com/", "", cleaned)
    cleaned = re.sub(r"^git@github\.com:", "", cleaned)
    return cleaned.strip("/")


def managed_projects(config: dict) -> list[dict]:
    return list(config.get("projects", []) or [])


def catalog_section(config: dict) -> dict:
    catalog = config.get("catalog")
    if not isinstance(catalog, dict):
        catalog = {}
        config["catalog"] = catalog
    return catalog


def catalog_projects(config: dict) -> list[dict]:
    catalog = catalog_section(config)
    projects = catalog.get("projects")
    if not isinstance(projects, list):
        projects = []
        catalog["projects"] = projects
    return projects


def all_projects(config: dict) -> list[dict]:
    return managed_projects(config) + catalog_projects(config)


def find_project(config: dict, project_name: str) -> dict | None:
    for project in all_projects(config):
        if project.get("name") == project_name:
            return project
    return None
