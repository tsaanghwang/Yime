from pinyin.yunmu_to_keys import YunmuConverter, YunmuConstants
import pytest

def test_conversion_basic():
    """Test basic conversion functionality"""
    converter = YunmuConverter()
    yunmu_dict = {"-i": ""} 
    result = converter.convert(yunmu_dict)
    assert result["-i"] == "ir"

def test_ao_conversion():
    """Test ao conversion rules"""
    converter = YunmuConverter()
    test_dict = {"ao": "", "iao": ""}
    result = converter.convert(test_dict)
    assert result["ao"] == "au"
    assert result["iao"] == "iau"

def test_special_conversions():
    """Test various special conversion cases"""
    converter = YunmuConverter()
    test_cases = {
        "iong": "",  # Should convert to vong
        "ing": "",   # Should convert to iong
        "e": "",     # Should convert to o
        "eng": "",   # Should convert to ong
        "in": "",    # Should convert to ien
        "ün": "",    # Should convert to üen
        "ueng": "",  # Should convert to uong
        "ong": "",   # Should convert to uong
        "ü": "",     # Should convert to v
        "ê": ""      # Should convert to e
    }
    result = converter.convert(test_cases)
    
    assert result["iong"] == "vong"
    assert result["ing"] == "iong"  
    assert result["e"] == "o"
    assert result["eng"] == "ong"
    assert result["in"] == "ien"
    assert result["ün"] == "üen"
    assert result["ueng"] == "uong"
    assert result["ong"] == "uong"
    assert result["ü"] == "v"
    assert "e" in result

def test_invalid_input():
    """Test error handling for invalid inputs"""
    converter = YunmuConverter()
    
    with pytest.raises(ValueError):
        converter.convert("not a dict")
        
    with pytest.raises(ValueError):
        converter.convert({1: "not a string"})

def test_stats_tracking():
    """Test statistics tracking functionality"""
    converter = YunmuConverter()
    test_dict = {"-i": "", "ao": "", "iong": ""}
    
    converter.convert(test_dict)
    stats = converter.get_stats()
    
    assert stats["total_conversions"] == 3
    assert stats["successful_conversions"] == 3
    assert stats["failed_conversions"] == 0
    assert stats["success_rate"] == 100.0
    assert "plugin_stats" in stats
    assert "rule_stats" in stats

def test_required_finals():
    """Test handling of required finals"""
    converter = YunmuConverter()
    constants = YunmuConstants()
    
    # Create dict with all required finals
    valid_dict = {k: "" for k in constants.REQUIRED_FINALS}
    result = converter.convert(valid_dict)
    
    # Should work with all required finals
    assert result is not None
    
    # Should fail if missing required finals
    invalid_dict = {"ao": ""}
    with pytest.raises(ValueError):
        converter.convert(invalid_dict)