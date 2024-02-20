// IMPORTS ---------------------------------------------------------------------

import filepath
import gleam/dict
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import glint.{type Command, CommandInput}
import glint/flag
import lustre/cli/esbuild
import lustre/cli/project.{type Module, type Type, Named, Variable}
import lustre/cli/utils.{map, replace, try}
import lustre/cli/step
import simplifile
import spinner
import gleam_community/ansi

// COMMANDS --------------------------------------------------------------------

pub fn app() -> Command(Nil) {
  let description =
    "
Build and bundle an entire Lustre application. The generated JavaScript module
calls your app's `main` function on page load and can be included in any Web
page without Gleam or Lustre being present.

This is different from using `gleam build` directly because it produces a single
JavaScript module for you to host or distribute.
    "

  glint.command(fn(input) {
    let CommandInput(flags: flags, ..) = input
    let assert Ok(minify) = flag.get_bool(flags, "minify")

    let result = {
      use <- step.new("Building your project")
      use project_name <- step.try(get_project_name())
      use module <- step.try(get_module_interface(project_name))
      use _ <- step.try(check_main_function(project_name, module))
      use <- step.done("✅ Project compiled successfully")

      write_app_entry_file(project_name)

      let root = project.root()
      let tempdir = filepath.join(root, "build/.lustre")
      let outdir = filepath.join(root, "priv/static")
      let _ = simplifile.create_directory_all(tempdir)
      let _ = simplifile.create_directory_all(outdir)
      let entry =
        "import { main } from '../dev/javascript/${project_name}/${project_name}.mjs';

          main();
        "
        |> string.replace("${project_name}", project_name)

      let entryfile = filepath.join(tempdir, "entry.mjs")
      let ext = case minify {
        True -> ".min.mjs"
        False -> ".mjs"
      }

      let outfile =
        project_name
        |> string.append(ext)
        |> filepath.join(outdir, _)

      let assert Ok(_) = simplifile.write(entryfile, entry)
      use _ <- step.try(bundle(entry, tempdir, outfile, minify))

      // Ok(Nil)
      todo
    }

    //case result {
    //  Ok(_) -> Nil
    //  Error(error) -> explain(error)
    //}
    Nil
  })
  |> glint.description(description)
  |> glint.unnamed_args(glint.EqArgs(0))
  |> glint.flag("minify", {
    let description = "Minify the output"
    let default = False

    flag.bool()
    |> flag.default(default)
    |> flag.description(description)
  })
}

pub fn component() -> Command(Nil) {
  let description =
    "
Build a Lustre component as a portable Web Component. The generated JavaScript
module can be included in any Web page and used without Gleam or Lustre being
present.
  "

  glint.command(fn(input) {
    let CommandInput(flags: flags, named_args: args, ..) = input
    let assert Ok(module_path) = dict.get(args, "module_path")
    let assert Ok(minify) = flag.get_bool(flags, "minify")

    let result = {
      let spinner =
        spinner.new("Preparing build")
        |> spinner.with_frames(spinner.snake_frames)
        |> spinner.with_colour(ansi.yellow)
        |> spinner.start

      spinner.set_text(spinner, "Building your project")
      use module <- result.try(get_module_interface(module_path))
      use _ <- result.try(check_component_name(module_path, module))
      use component <- result.try(find_component(module_path, module))

      spinner.set_text(spinner, "Generating entry file")
      let root = project.root()
      let tempdir = filepath.join(root, "build/.lustre")
      let outdir = filepath.join(root, "priv/static")

      let _ = simplifile.create_directory_all(tempdir)
      let _ = simplifile.create_directory_all(outdir)

      use project_name <- result.try(get_project_name())
      let entry =
        "import { register } from '../dev/javascript/lustre/client-component.ffi.mjs';
         import { name, ${component} as component } from '../dev/javascript/${project_name}/${module_path}.mjs';

         register(component(), name);
        "
        |> string.replace("${component}", component)
        |> string.replace("${project_name}", project_name)
        |> string.replace("${module_path}", module_path)

      let entryfile = filepath.join(tempdir, "entry.mjs")
      let ext = case minify {
        True -> ".min.mjs"
        False -> ".mjs"
      }
      let assert Ok(outfile) =
        string.split(module_path, "/")
        |> list.last
        |> result.map(string.append(_, ext))
        |> result.map(filepath.join(outdir, _))

      let assert Ok(_) = simplifile.write(entryfile, entry)
      use _ <- result.try(bundle(entry, tempdir, outfile, minify))

      spinner.stop(spinner)
      Ok(Nil)
    }

    case result {
      Ok(_) -> Nil
      Error(error) -> explain(error)
    }
  })
  |> glint.description(description)
  |> glint.named_args(["module_path"])
  |> glint.unnamed_args(glint.EqArgs(1))
  |> glint.flag("minify", {
    let description = "Minify the output"
    let default = False

    flag.bool()
    |> flag.default(default)
    |> flag.description(description)
  })
}

// ERROR HANDLING --------------------------------------------------------------

type Error {
  BuildError
  BundleError(esbuild.Error)
  ComponentMissing(module: String)
  MainMissing(module: String)
  ModuleMissing(module: String)
  NameIncorrectType(module: String, got: project.Type)
  NameMissing(module: String)
}

fn explain(error: Error) -> Nil {
  error
  |> string.inspect
  |> io.println
}

// STEPS -----------------------------------------------------------------------

fn get_project_name() -> Result(String, Error) {
  use config <- try(project.config(), replace(with: BuildError))
  Ok(config.name)
}

fn get_module_interface(module_path: String) -> Result(Module, Error) {
  use interface <- try(project.interface(), replace(with: BuildError))
  use module <- try(
    dict.get(interface.modules, module_path),
    replace(with: ModuleMissing(module_path)),
  )

  Ok(module)
}

fn check_main_function(
  module_path: String,
  module: Module,
) -> Result(Nil, Error) {
  case dict.has_key(module.functions, "main") {
    True -> Ok(Nil)
    False -> Error(MainMissing(module_path))
  }
}

fn check_component_name(
  module_path: String,
  module: Module,
) -> Result(Nil, Error) {
  use component_name <- try(
    dict.get(module.constants, "name"),
    replace(with: NameMissing(module_path)),
  )

  case is_string_type(component_name) {
    True -> Ok(Nil)
    False -> Error(NameIncorrectType(module_path, component_name))
  }
}

fn find_component(module_path: String, module: Module) -> Result(String, Error) {
  let functions = dict.to_list(module.functions)
  let error = Error(ComponentMissing(module_path))

  use _, #(name, t) <- list.fold_until(functions, error)
  case t.parameters, is_compatible_app_type(t.return) {
    [], True -> list.Stop(Ok(name))
    _, _ -> list.Continue(error)
  }
}

fn bundle(
  entry: String,
  tempdir: String,
  outfile: String,
  minify: Bool,
) -> Result(Nil, Error) {
  let entryfile = filepath.join(tempdir, "entry.mjs")
  let assert Ok(_) = simplifile.write(entryfile, entry)

  use _ <- try(
    esbuild.bundle(entryfile, outfile, minify),
    map(with: BundleError),
  )

  Ok(Nil)
}

// UTILS -----------------------------------------------------------------------

fn is_string_type(t: Type) -> Bool {
  case t {
    Named(name: "String", package: "", module: "gleam", parameters: []) -> True
    _ -> False
  }
}

fn is_nil_type(t: Type) -> Bool {
  case t {
    Named(name: "Nil", package: "", module: "gleam", parameters: []) -> True
    _ -> False
  }
}

fn is_type_variable(t: Type) -> Bool {
  case t {
    Variable(..) -> True
    _ -> False
  }
}

fn is_compatible_app_type(t: Type) -> Bool {
  case t {
    Named(
      name: "App",
      package: "lustre",
      module: "lustre",
      parameters: [flags, ..],
    ) -> is_nil_type(flags) || is_type_variable(flags)
    _ -> False
  }
}
