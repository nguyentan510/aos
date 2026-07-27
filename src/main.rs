mod cli;
mod extension;
mod intelligence;
mod model;
mod repository;
mod setup;
mod work;

use std::process::ExitCode;

fn main() -> ExitCode {
    let arguments = std::env::args().skip(1);
    match cli::parse(arguments) {
        Ok(options) => {
            let result = cli::run(options);
            result.render();
            ExitCode::from(result.exit_code)
        }
        Err(error) => {
            let result = cli::usage_error(error);
            result.render();
            ExitCode::from(result.exit_code)
        }
    }
}
