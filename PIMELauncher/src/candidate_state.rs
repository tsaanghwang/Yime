//! Required state boundary for the separately built DP1 candidate launcher.
use serde::Deserialize;
use std::fs;
use std::path::{Component, Path, PathBuf};
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CandidateState {
    pub schema_version: String,
    pub install_root: PathBuf,
    pub state_root: PathBuf,
    pub target_user_sid: String,
}

fn ordinary_absolute(path: &Path) -> bool {
    let text = path.to_string_lossy();
    path.is_absolute() && text.len() > 3 && !text.contains('/') && !text.ends_with('\\')
        && !path.components().any(|c| matches!(c, Component::ParentDir | Component::CurDir))
        && !text.starts_with(r"\\")
}

pub fn parse_and_validate(bytes: &[u8], install_root: &Path, sid: &str) -> Result<CandidateState, String> {
    if bytes.is_empty() || bytes.len() > 16 * 1024 { return Err("invalid configuration length".into()); }
    let config: CandidateState = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
    if config.schema_version != "yime-rime-pime-candidate-state-v1" || config.target_user_sid != sid
        || !ordinary_absolute(&config.install_root) || !ordinary_absolute(&config.state_root)
        || !config.install_root.to_string_lossy().eq_ignore_ascii_case(&install_root.to_string_lossy()) {
        return Err("configuration root or SID binding mismatch".into());
    }
    let root = config.install_root.to_string_lossy().to_lowercase();
    let state = config.state_root.to_string_lossy().to_lowercase();
    if root == state || root.starts_with(&(state.clone() + "\\")) || state.starts_with(&(root + "\\")) {
        return Err("installation and writable state overlap".into());
    }
    Ok(config)
}

fn verify_ordinary_directory(path: &Path) -> Result<(), String> {
    use std::os::windows::fs::MetadataExt;
    for ancestor in path.ancestors() {
        let metadata = fs::symlink_metadata(ancestor).map_err(|e| e.to_string())?;
        if !metadata.is_dir() || metadata.file_attributes() & 0x400 != 0 {
            return Err("state/configuration ancestor is not an ordinary directory".into());
        }
    }
    Ok(())
}

pub fn apply() -> Result<(), String> {
    use std::os::windows::fs::MetadataExt;
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let root = exe.parent().ok_or("launcher has no parent")?;
    verify_ordinary_directory(root)?;
    let path = root.join("rime-pime-candidate-state.json");
    let metadata = fs::symlink_metadata(&path).map_err(|e| e.to_string())?;
    if !metadata.is_file() || metadata.file_attributes() & 0x400 != 0 || metadata.len() > 16 * 1024 {
        return Err("configuration is not an ordinary bounded file".into());
    }
    let config = parse_and_validate(&fs::read(&path).map_err(|e| e.to_string())?, root, &crate::maintenance::current_user_sid()?)?;
    let roaming = config.state_root.join("Roaming");
    let local = config.state_root.join("Local");
    verify_ordinary_directory(&roaming)?;
    verify_ordinary_directory(&local)?;
    std::env::set_var("APPDATA", roaming);
    std::env::set_var("LOCALAPPDATA", local);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn valid() -> serde_json::Value { serde_json::json!({"schema_version":"yime-rime-pime-candidate-state-v1","install_root":r"C:\Candidate","state_root":r"C:\CandidateState","target_user_sid":"S-1-5-21-1"}) }
    fn parse(v: &serde_json::Value) -> bool { parse_and_validate(&serde_json::to_vec(v).unwrap(), Path::new(r"C:\Candidate"), "S-1-5-21-1").is_ok() }
    #[test] fn valid_config_binds_separate_state() { assert!(parse(&valid())); }
    #[test] fn rejects_missing_wrong_and_foreign_fields() {
        for field in ["schema_version", "install_root", "state_root", "target_user_sid"] {
            let mut v=valid(); v.as_object_mut().unwrap().remove(field); assert!(!parse(&v));
            let mut v=valid(); v[field]=serde_json::json!([]); assert!(!parse(&v));
        }
        for (field,value) in [("install_root",r"C:\Other"),("target_user_sid","S-1-5-21-2"),("state_root",r"C:\Candidate\State"),("state_root",r"C:\Candidate"),("state_root",r"relative"),("state_root",r"\\server\share"),("state_root",r"C:\State\..\Candidate"),("state_root","C:/Candidate/State"),("state_root","C:\\")] {
            let mut v=valid(); v[field]=value.into(); assert!(!parse(&v), "{field}: {value}");
        }
        let mut v=valid(); v["unknown"]=true.into(); assert!(!parse(&v));
    }
    #[test] fn rejects_duplicate_keys() {
        let text=r#"{"schema_version":"yime-rime-pime-candidate-state-v1","schema_version":"yime-rime-pime-candidate-state-v1","install_root":"C:\\Candidate","state_root":"C:\\State","target_user_sid":"S-1-5-21-1"}"#;
        assert!(parse_and_validate(text.as_bytes(),Path::new(r"C:\Candidate"),"S-1-5-21-1").is_err());
    }
    #[test] fn missing_installed_config_cannot_fall_back_to_inherited_state() {
        let root=std::env::current_exe().unwrap().parent().unwrap().to_path_buf();
        assert!(!root.join("rime-pime-candidate-state.json").exists(), "test binary directory must not contain installed candidate state");
        let old_roaming=std::env::var_os("APPDATA"); let old_local=std::env::var_os("LOCALAPPDATA");
        assert!(apply().is_err());
        assert_eq!(old_roaming,std::env::var_os("APPDATA"));
        assert_eq!(old_local,std::env::var_os("LOCALAPPDATA"));
    }
}
