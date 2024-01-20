// IMPORTS ---------------------------------------------------------------------

import gleam/bool
import gleam/dynamic.{type DecodeError, type Dynamic, DecodeError}
import gleam/erlang/process.{type Selector}
import gleam/int
import gleam/json.{type Json}
import gleam/result
import lustre/attribute.{type Attribute, attribute}
import lustre/effect.{type Effect}
import lustre/element.{type Element, element}
import lustre/internals/constants
import lustre/runtime.{type Action, Attrs, Event, SetSelector}

// ELEMENTS --------------------------------------------------------------------

/// A simple wrapper to render a `<lustre-server-component>` element. 
/// 
pub fn component(attrs: List(Attribute(msg))) -> Element(msg) {
  element("lustre-server-component", attrs, [])
}

// ATTRIBUTES ------------------------------------------------------------------

/// The `route` attribute should always be included on a [`component`](#component)
/// to tell the client runtime what path to initiate the WebSocket connection on.
/// 
/// 
/// 
pub fn route(path: String) -> Attribute(msg) {
  attribute("route", path)
}

/// Ocassionally you may want to attach custom data to an event sent to the server.
/// This could be used to include a hash of the current build to detect if the
/// event was sent from a stale client.
/// 
/// ```gleam
/// 
/// ```
/// 
pub fn data(json: Json) -> Attribute(msg) {
  json
  |> json.to_string
  |> attribute("data-lustre-data", _)
}

/// Properties of the JavaScript event object are typically not serialisable. 
/// This means if we want to pass them to the server we need to copy them into
/// a new object first.
/// 
/// This attribute tells Lustre what properties to include. Properties can come
/// from nested objects by using dot notation. For example, you could include the
/// `id` of the target `element` by passing `["target.id"]`.
/// 
/// ```gleam
/// import gleam/dynamic
/// import gleam/result.{try}
/// import lustre/element.{type Element}
/// import lustre/element/html
/// import lustre/event
/// import lustre/server
/// 
/// pub fn custom_button(on_click: fn(String) -> msg) -> Element(msg) {
///   let handler = fn(event) {
///     use target <- try(dynamic.field("target", dynamic.dynamic)(event))
///     use id <- try(dynamic.field("id", dynamic.string)(target))
/// 
///     Ok(on_click(id))
///   }
/// 
///   html.button([event.on_click(handler), server.include(["target.id"])], [
///     element.text("Click me!")
///   ])
/// }
/// ```
/// 
pub fn include(properties: List(String)) -> Attribute(msg) {
  properties
  |> json.array(json.string)
  |> json.to_string
  |> attribute("data-lustre-include", _)
}

// EFFECTS ---------------------------------------------------------------------

///
/// 
pub fn emit(event: String, data: Json) -> Effect(msg) {
  effect.event(event, data)
}

@target(erlang)
///
/// 
pub fn selector(sel: Selector(Action(runtime, msg))) -> Effect(msg) {
  use _ <- effect.from
  let self = process.new_subject()

  process.send(self, SetSelector(sel))
}

// DECODERS --------------------------------------------------------------------

pub fn decode_action(
  dyn: Dynamic,
) -> Result(Action(runtime, msg), List(DecodeError)) {
  dynamic.any([decode_event, decode_attrs])(dyn)
}

///
/// 
fn decode_event(
  dyn: Dynamic,
) -> Result(Action(runtime, msg), List(DecodeError)) {
  use #(kind, name, data) <- result.try(dynamic.tuple3(
    dynamic.int,
    dynamic.dynamic,
    dynamic.dynamic,
  )(dyn))
  use <- bool.guard(
    kind != constants.event,
    Error([
      DecodeError(
        path: ["0"],
        found: int.to_string(kind),
        expected: int.to_string(constants.event),
      ),
    ]),
  )
  use name <- result.try(dynamic.string(name))

  Ok(Event(name, data))
}

fn decode_attrs(
  dyn: Dynamic,
) -> Result(Action(runtime, msg), List(DecodeError)) {
  use list <- result.try(dynamic.list(dynamic.dynamic)(dyn))
  case list {
    [kind, attrs] -> {
      use kind <- result.try(dynamic.int(kind))
      use <- bool.guard(
        kind != constants.attrs,
        Error([
          DecodeError(
            path: ["0"],
            found: int.to_string(kind),
            expected: int.to_string(constants.attrs),
          ),
        ]),
      )
      use attrs <- result.try(dynamic.list(decode_attr)(attrs))
      Ok(Attrs(attrs))
    }
    _ ->
      Error([
        DecodeError(
          path: [],
          found: dynamic.classify(dyn),
          expected: "a tuple of 2 elements",
        ),
      ])
  }
}

fn decode_attr(dyn: Dynamic) -> Result(#(String, Dynamic), List(DecodeError)) {
  use list <- result.try(dynamic.list(dynamic.dynamic)(dyn))
  case list {
    [key, value] -> {
      use key <- result.try(dynamic.string(key))
      Ok(#(key, value))
    }
    _ ->
      Error([
        DecodeError(
          path: [],
          found: dynamic.classify(dyn),
          expected: "a tuple of 2 elements",
        ),
      ])
  }
}
