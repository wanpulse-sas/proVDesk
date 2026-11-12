fn main() {
    println!("cargo:rerun-if-env-changed=RUSTDESK_APP_NAME");
    println!("cargo:rerun-if-env-changed=RUSTDESK_EDITOR_NAME");
    #[cfg(windows)]
    {
        use std::io::Write;
        let mut res = winres::WindowsResource::new();
        res.set_icon("../../res/icon.ico")
            .set_language(winapi::um::winnt::MAKELANGID(
                winapi::um::winnt::LANG_ENGLISH,
                winapi::um::winnt::SUBLANG_ENGLISH_US,
            ))
            .set_manifest_file("../../res/manifest.xml");
        if let Ok(app_name) = std::env::var("RUSTDESK_APP_NAME") {
            res.set("ProductName", &app_name)
                .set("OriginalFilename", &format!("{app_name}.exe"))
                .set("FileDescription", &format!("{app_name} Remote Desktop"));
        }
        if let Ok(editor) = std::env::var("RUSTDESK_EDITOR_NAME") {
            res.set("CompanyName", &editor);
        }
        match res.compile() {
            Err(e) => {
                write!(std::io::stderr(), "{}", e).unwrap();
                std::process::exit(1);
            }
            Ok(_) => {}
        }
    }
}
