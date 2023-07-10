//// Lustre is a declarative framework for building Web apps in Gleam. 

// IMPORTS ---------------------------------------------------------------------

import gleam/result
import lustre/cmd.{Cmd}
import lustre/element.{Element}

// TYPES -----------------------------------------------------------------------

/// An `App` describes a Lustre application: what state it holds and what kind
/// of actions get dispatched to update that model. The only useful thing you can
/// do with an `App` is pass it to [`start`](#start).
///
/// You can construct an `App` from the two constructors exposed in this module:
/// [`basic`](#basic) and [`application`](#application). Although you can't do
/// anything but [`start`](#start) them, the constructors are separated in case
/// you want to set up an application but defer starting it until some later point
/// in time.
///
/// ```text
///                                       +--------+
///                                       |        |
///                                       | update |
///                                       |        |
///                                       +--------+
///                                         ^    |
///                                         |    | 
///                                     Msg |    | #(Model, Cmd(Msg))
///                                         |    |
///                                         |    v
/// +------+                      +------------------------+
/// |      |  #(Model, Cmd(Msg))  |                        |
/// | init |--------------------->|     Lustre Runtime     |
/// |      |                      |                        |
/// +------+                      +------------------------+
///                                         ^    |
///                                         |    |
///                                     Msg |    | Model
///                                         |    |
///                                         |    v
///                                       +--------+
///                                       |        |
///                                       | render |
///                                       |        |
///                                       +--------+
/// ```
///
/// <small>Someone please PR the Gleam docs generator to fix the monospace font,
/// thanks! 💖</small>
///
pub external type App(model, msg)

pub type Error {
  ElementNotFound
}

// These types aren't exposed, but they're just here to try and shrink the type
// annotations for `App` and `application` a little bit. When generating docs,
// Gleam automatically expands type aliases so this is purely for the benefit of
// those reading the source.
//

type Update(model, msg) =
  fn(model, msg) -> #(model, Cmd(msg))

type Render(model, msg) =
  fn(model) -> Element(msg)

// CONSTRUCTORS ----------------------------------------------------------------

/// Create a basic lustre app that just renders some element on the page.
/// Note that this doesn't mean the content is static! With `element.stateful`
/// you can still create components with local state.
///
/// Basic lustre apps don't have any *global* application state and so the
/// plumbing is a lot simpler. If you find yourself passing lots of state around,
/// you might want to consider using [`simple`](#simple) or [`application`](#application)
/// instead.
///
/// ```gleam
/// import lustre
/// import lustre/element
/// 
/// pub fn main () {
///   let app = lustre.element(
///     element.h1([], [
///       element.text("Hello, world!") 
///     ])
///   )
/// 
///   assert Ok(_) = lustre.start(app, "#root")
/// }
/// ```
///
pub fn element(element: Element(msg)) -> App(Nil, msg) {
  let init = fn() { #(Nil, cmd.none()) }
  let update = fn(_, _) { #(Nil, cmd.none()) }
  let render = fn(_) { element }

  application(init, update, render)
}

/// If you start off with a simple `[element`](#element) app, you may find
/// yourself leaning on [`stateful`](./lustrel/element.html#stateful) elements
/// to manage model used throughout your app. If that's the case or if you know
/// you need some global model from the get-go, you might want to construct a 
/// [`simple`](#simple) app instead.
///
/// This is one app constructor that allows your HTML elements to dispatch actions
/// to update your program model. 
///
/// ```gleam
/// import gleam/int
/// import lustre
/// import lustre/element
/// import lustre/event
/// 
/// type Msg {
///   Decr
///   Incr
/// }
/// 
/// pub fn main () {
///   let init = 0
///
///   let update = fn (model, msg) {
///     case msg {
///       Decr -> model - 1
///       Incr -> model + 1
///     }
///   }
///
///   let render = fn (model) {
///     element.div([], [
///       element.button([ event.on_click(Decr) ], [
///         element.text("-")
///       ]),
///
///       element.text(int.to_string(model)),
///
///       element.button([ event.on_click(Incr) ], [
///         element.text("+")
///       ])
///     ])
///   }
/// 
///   let app = lustre.simple(init, update, render)
///   assert Ok(_) = lustre.start(app, "#root")
/// }
/// ```
///
pub fn simple(
  init: fn() -> model,
  update: fn(model, msg) -> model,
  render: fn(model) -> Element(msg),
) -> App(model, msg) {
  let init = fn() { #(init(), cmd.none()) }
  let update = fn(model, msg) { #(update(model, msg), cmd.none()) }

  application(init, update, render)
}

/// An evolution of a [`simple`](#simple) app that allows you to return a
/// [`Cmd`](./lustre/cmd.html#Cmd) from your `init` and `update`s. Commands give
/// us a way to perform side effects like sending an HTTP request or running a
/// timer and then dispatch actions back to the runtime to trigger an `update`.
///
///```
/// import lustre
/// import lustre/cmd
/// import lustre/element
/// 
/// pub fn main () {
///   let init = #(0, tick())
///
///   let update = fn (model, msg) {
///     case msg {
///       Tick -> #(model + 1, tick())
///     }
///   }
///
///   let render = fn (model) {
///     element.div([], [
///       element.text("Time elapsed: ")
///       element.text(int.to_string(model))
///     ])
///   }
///   
///   let app = lustre.simple(init, update, render)
///   assert Ok(_) = lustre.start(app, "#root")   
/// }
/// 
/// fn tick () -> Cmd(Msg) {
///   cmd.from(fn (dispatch) {
///     setInterval(fn () {
///       dispatch(Tick)
///     }, 1000)
///   })
/// }
/// 
/// external fn set_timeout (f: fn () -> a, delay: Int) -> Nil 
///   = "" "window.setTimeout"
///```
pub external fn application(
  init: fn() -> #(model, Cmd(msg)),
  update: Update(model, msg),
  render: Render(model, msg),
) -> App(model, msg) =
  "./lustre.ffi.mjs" "setup"

// EFFECTS ---------------------------------------------------------------------

/// Once you have created a app with either `basic` or `application`, you 
/// need to actually start it! This function will mount your app to the DOM
/// node that matches the query selector you provide.
///
/// If everything mounted OK, we'll get back a dispatch function that you can 
/// call to send actions to your app and trigger an update. 
///
///```
/// import lustre
///
/// pub fn main () {
///   let app = lustre.appliation(init, update, render)
///   assert Ok(dispatch) = lustre.start(app, "#root")
/// 
///   dispatch(Incr)
///   dispatch(Incr)
///   dispatch(Incr)
/// }
///```
///
/// This may not seem super useful at first, but by returning this dispatch
/// function from your `main` (or elsewhere) you can get events into your Lustre
/// app from the outside world.
///
pub fn start(
  app: App(model, msg),
  selector: String,
) -> Result(fn(msg) -> Nil, Error) {
  start_(app, selector)
  |> result.replace_error(ElementNotFound)
}

external fn start_(
  app: App(model, msg),
  selector: String,
) -> Result(fn(msg) -> Nil, Nil) =
  "./lustre.ffi.mjs" "start"
