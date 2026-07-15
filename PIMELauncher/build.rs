use std::env;
use std::fs;
use std::path::PathBuf;

fn main() {
    let manifest_dir = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let version_path = manifest_dir.join("..").join("version.txt");
    println!("cargo:rerun-if-changed={}", version_path.display());

    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        return;
    }

    let version = fs::read_to_string(&version_path)
        .unwrap_or_else(|error| panic!("could not read {}: {error}", version_path.display()));
    let version = version.trim();
    let numeric_version = numeric_version(version);

    let mut resource = winresource::WindowsResource::new();
    resource
        .set("CompanyName", "YIME Project")
        .set("FileDescription", "YIME Launcher")
        .set("FileVersion", version)
        .set("InternalName", "PIMELauncher")
        .set("OriginalFilename", "PIMELauncher.exe")
        .set("ProductName", "YIME")
        .set("ProductVersion", version)
        .set_version_info(winresource::VersionInfo::FILEVERSION, numeric_version)
        .set_version_info(winresource::VersionInfo::PRODUCTVERSION, numeric_version);
    resource
        .compile()
        .expect("could not compile PIMELauncher VERSIONINFO");
}

fn numeric_version(version: &str) -> u64 {
    let core = version.split_once('-').map_or(version, |(core, _)| core);
    let mut parts = core.split('.');
    let major = version_part(parts.next(), "major", version);
    let minor = version_part(parts.next(), "minor", version);
    let patch = version_part(parts.next(), "patch", version);
    if parts.next().is_some() {
        panic!("version must contain exactly three numeric components: {version}");
    }
    (major << 48) | (minor << 32) | (patch << 16)
}

fn version_part(part: Option<&str>, name: &str, version: &str) -> u64 {
    let value = part
        .unwrap_or_else(|| panic!("version is missing its {name} component: {version}"))
        .parse::<u16>()
        .unwrap_or_else(|_| panic!("version {name} component is not a 16-bit integer: {version}"));
    u64::from(value)
}

#[cfg(test)]
mod tests {
    use super::numeric_version;

    #[test]
    fn encodes_release_and_development_versions() {
        assert_eq!(numeric_version("1.4.0"), 0x0001_0004_0000_0000);
        assert_eq!(numeric_version("1.5.2-dev"), 0x0001_0005_0002_0000);
    }
}
