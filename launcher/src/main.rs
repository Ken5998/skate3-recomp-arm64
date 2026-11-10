//! Skate 3 launcher for ARM64 Linux handhelds (ArmadaOS on the Retroid
//! Pocket 6, or any aarch64 Linux): builds Skate 3 Recomp, Skate 3 (Xbox 360)
//! recompiled, from the player's own disc with this repository's scripts,
//! keeps it up to date, plays it and adds it to Steam.

mod app;
mod tasks;

const HELP: &str = "Skate 3 launcher for ARM64

Without options the launcher window opens. It builds Skate 3 (Skate 3 Recomp) in
~/.local/share/Skate3Recomp-arm64 from your own Skate 3 (Xbox 360) disc
image, with the scripts of https://github.com/Ken5998/skate3-recomp-arm64.

  --help     this text
  --version  the launcher's version";

fn main() {
    match std::env::args().nth(1).as_deref() {
        Some("--help" | "-h") => {
            println!("{HELP}");
            return;
        }
        Some("--version" | "-V") => {
            println!("{}", env!("CARGO_PKG_VERSION"));
            return;
        }
        _ => {}
    }

    let options = eframe::NativeOptions {
        viewport: eframe::egui::ViewportBuilder::default()
            .with_title("Skate 3")
            .with_app_id("skate3-launcher")
            .with_inner_size([860.0, 620.0])
            .with_min_inner_size([640.0, 480.0]),
        ..Default::default()
    };
    let result = eframe::run_native(
        "Skate 3",
        options,
        Box::new(|cc| {
            cc.egui_ctx.set_theme(eframe::egui::Theme::Dark);
            Ok(Box::new(app::LauncherApp::new(cc.egui_ctx.clone())))
        }),
    );
    if let Err(e) = result {
        eprintln!("The launcher window could not open: {e}");
        std::process::exit(1);
    }
}
