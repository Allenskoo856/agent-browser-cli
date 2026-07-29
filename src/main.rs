mod cli;
mod config;
mod html;
mod open_target;
mod playwright_runtime;
mod protocol;
mod server;

use anyhow::Result;

fn main() -> Result<()> {
    cli::run()
}
