//! Seals and opens the quiet side's *source* file, so no plaintext secret ever
//! sits on disk in the repository.
//!
//! Usage:
//!
//!     AMZORA_PASSPHRASE='...' cargo run -p lexicon_forge --bin seal_source -- lock
//!     AMZORA_PASSPHRASE='...' cargo run -p lexicon_forge --bin seal_source -- open
//!
//! `lock` turns `oracle/tools/gate.txt` into `oracle/tools/gate.sealed` and
//! removes the plaintext. `open` reverses it for editing. The passphrase comes
//! from the environment and is never written anywhere.
//!
//! The cipher is the project's own `shroud`, keyed by a passphrase digest, so
//! the toolchain stays dependency-free and there is one cipher to audit. An
//! attacker with the repository has ciphertext and no key.

use std::env;
use std::fs;
use std::path::PathBuf;

#[path = "../../../oracle/src/entropy.rs"]
mod entropy;
#[path = "../../../oracle/src/crypt.rs"]
mod crypt;

use crypt::{shroud, unshroud};
use entropy::imprint;

/// Derives the envelope key from the passphrase.
///
/// The digest is salted so the same passphrase used elsewhere in the
/// toolchain never yields the same key here.
fn envelope_key(passphrase: &str) -> u64 {
    let salted = format!("amzora.gate.v1|{passphrase}");
    imprint(salted.as_bytes(), 0x51C3_9E7B_2D48_A0F6)
}

fn main() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("oracle");
    let plain_path = root.join("tools").join("gate.txt");
    let sealed_path = root.join("tools").join("gate.sealed");

    let args: Vec<String> = env::args().collect();
    let mode = args.get(1).map(String::as_str).unwrap_or("");

    let passphrase = match env::var("AMZORA_PASSPHRASE") {
        Ok(value) if !value.is_empty() => value,
        _ => {
            eprintln!("AMZORA_PASSPHRASE is not set");
            std::process::exit(2);
        }
    };
    let key = envelope_key(&passphrase);

    match mode {
        // Plaintext -> sealed. The plaintext is removed afterwards so the
        // working tree never holds both.
        "lock" => {
            let plain = match fs::read(&plain_path) {
                Ok(bytes) => bytes,
                Err(why) => {
                    eprintln!("cannot read {}: {why}", plain_path.display());
                    std::process::exit(2);
                }
            };
            let sealed = shroud(&plain, key);
            if let Err(why) = fs::write(&sealed_path, &sealed) {
                eprintln!("cannot write {}: {why}", sealed_path.display());
                std::process::exit(3);
            }
            let _ = fs::remove_file(&plain_path);
            println!(
                "locked {} bytes -> {} ({} bytes); plaintext removed",
                plain.len(),
                sealed_path.display(),
                sealed.len()
            );
        }
        // Sealed -> plaintext, for editing. Refuses to clobber an existing
        // plaintext file so a stray run cannot lose edits.
        "open" => {
            if plain_path.exists() {
                eprintln!("{} already exists; move it aside first", plain_path.display());
                std::process::exit(4);
            }
            let sealed = match fs::read(&sealed_path) {
                Ok(bytes) => bytes,
                Err(why) => {
                    eprintln!("cannot read {}: {why}", sealed_path.display());
                    std::process::exit(2);
                }
            };
            let Some(plain) = unshroud(&sealed, key) else {
                eprintln!("wrong passphrase, or the file is damaged");
                std::process::exit(5);
            };
            if let Err(why) = fs::write(&plain_path, &plain) {
                eprintln!("cannot write {}: {why}", plain_path.display());
                std::process::exit(3);
            }
            println!("opened {} bytes -> {}", plain.len(), plain_path.display());
        }
        _ => {
            eprintln!("usage: seal_source <lock|open>");
            std::process::exit(1);
        }
    }
}
