import json
from pathlib import Path
from datetime import datetime

def generate_report():
    report = {
        "timestamp": datetime.now().isoformat(),
        "workflows": {
            "backend": {"status": "pending", "coverage": 0},
            "frontend": {"status": "pending", "tests": 0},
            "docs": {"status": "pending"}
        }
    }
    
    # 解析各工作流结果
    if Path("python-coverage.json").exists():
        with open("python-coverage.json") as f:
            cov = json.load(f)
            report["workflows"]["backend"].update({
                "status": "success",
                "coverage": cov["totals"]["percent_covered"]
            })
            
    # 保存统一报告
    with open("ci-summary.json", "w") as f:
        json.dump(report, f, indent=2)

if __name__ == "__main__":
    generate_report()