import unittest
import yaml
from unittest.mock import patch

class TestPyPIPublishCondition(unittest.TestCase):
    """测试 GitHub Actions 工作流中 PyPI 发布条件的单元测试"""
    
    def setUp(self):
        """加载 GitHub Actions 工作流文件"""
        with open('.github/workflows/release.yml') as f:
            self.workflow = yaml.safe_load(f)
        
        # 找到发布步骤
        self.publish_step = None
        for step in self.workflow['jobs']['build-and-publish']['steps']:
            if step.get('name') == 'Publish to PyPI':
                self.publish_step = step
                break
    
    def test_publish_step_exists(self):
        """测试发布步骤是否存在"""
        self.assertIsNotNone(self.publish_step, "Publish to PyPI step not found in workflow")
        self.assertIn('if', self.publish_step, "Condition 'if' not found in publish step")
    
    def test_condition_structure(self):
        """测试条件语句的结构"""
        condition = self.publish_step['if']
        self.assertEqual(condition, "secrets.PYPI_API_TOKEN != ''", 
                        "Condition should check for non-empty PYPI_API_TOKEN")
    
    @patch.dict('os.environ', {'PYPI_API_TOKEN': ''})
    def test_condition_with_empty_token(self):
        """测试当 PYPI_API_TOKEN 为空时的行为"""
        condition = self.publish_step['if']
        self.assertTrue(eval(condition.replace('secrets.', 'os.environ.get("") != ')))
    
    @patch.dict('os.environ', {'PYPI_API_TOKEN': 'valid_token'})
    def test_condition_with_valid_token(self):
        """测试当 PYPI_API_TOKEN 有值时的行为"""
        condition = self.publish_step['if']
        self.assertTrue(eval(condition.replace('secrets.', 'os.environ.get("") != ')))

if __name__ == '__main__':
    unittest.main()