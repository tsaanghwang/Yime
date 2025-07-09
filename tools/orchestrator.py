import json
import subprocess
from datetime import datetime
import sys
from pathlib import Path

WORKFLOW = [
    {
        "script": "finals_classifier.py",
        "input": "external_data/finals_IPA_mapping.json",
        "output": "internal_data/classified_finals.json",
        "description": "韵母分类法，生成classified_finals.json"
    },
    {
        "script": "pianyin_analyzer.py",
        "input": "internal_data/classified_finals.json",
        "output": "internal_data/pianyin_analyzer.json",
        "description": "干音分析，生成片音序列"
    },
    {
        "script": "pianyin_counter.py", 
        "input": "internal_data/pianyin_analyzer.json",
        "output": "internal_data/pianyin_counter.json",
        "description": "统计音标和片音出现频率"
    },
    {
        "script": "yinyuan_pianyin_mapping.py",
        "input": "internal_data/pianyin_counter.json",
        "output": "internal_data/yinyuan_pianyin_mapping.json",
        "description": "建立音元到片音的映射关系"
    }
]

class WorkflowExecutor:
    def __init__(self):
        self.log_file = "internal_data/workflow_log.json"
        self.status = {
            "start_time": datetime.now().isoformat(),
            "steps": [],
            "success": False
        }
        
    def validate_file(self, filepath):
        if not Path(filepath).exists():
            raise FileNotFoundError(f"Required file not found: {filepath}")
            
    def run_script(self, script_config):
        script_path = f"tools/{script_config['script']}"
        self.validate_file(script_path)
        self.validate_file(script_config["input"])
        
        step = {
            "script": script_config["script"],
            "start_time": datetime.now().isoformat(),
            "status": "running"
        }
        self.status["steps"].append(step)
        
        try:
            result = subprocess.run(
                ["python", script_path],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                step["status"] = "completed"
                step["end_time"] = datetime.now().isoformat()
                step["output"] = result.stdout.strip()
                self.validate_file(script_config["output"])
            else:
                step["status"] = "failed"
                step["error"] = result.stderr.strip()
                raise RuntimeError(f"Script failed: {script_config['script']}")
                
        except Exception as e:
            step["status"] = "failed"
            step["error"] = str(e)
            raise
            
    def execute(self):
        try:
            for step in WORKFLOW:
                self.run_script(step)
                
            self.status["success"] = True
            self.status["end_time"] = datetime.now().isoformat()
            return True
            
        except Exception as e:
            self.status["error"] = str(e)
            return False
            
        finally:
            with open(self.log_file, "w") as f:
                json.dump(self.status, f, indent=2)

if __name__ == "__main__":
    executor = WorkflowExecutor()
    success = executor.execute()
    
    if success:
        print("Workflow completed successfully")
        sys.exit(0)
    else:
        print("Workflow failed")
        sys.exit(1)