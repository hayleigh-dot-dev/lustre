// IMPORTS ---------------------------------------------------------------------

import gleam/dict.{type Dict}
import gleam/dynamic.{type Decoder, type Dynamic}
import gleam/erlang/process.{type Selector, type Subject}
import gleam/function.{identity}
import gleam/list
import gleam/json.{type Json}
import gleam/option.{Some}
import gleam/otp/actor.{type Next, type StartError, Spec}
import gleam/result
import lustre/effect.{type Effect}
import lustre/element.{type Element, type Patch}
import lustre/internals/patch.{Diff, Init}
import lustre/internals/vdom

// TYPES -----------------------------------------------------------------------

///
///
type State(runtime, model, msg) {
  State(
    self: Subject(Action(runtime, msg)),
    model: model,
    update: fn(model, msg) -> #(model, Effect(msg)),
    view: fn(model) -> Element(msg),
    html: Element(msg),
    renderers: Dict(Dynamic, fn(Patch(msg)) -> Nil),
    handlers: Dict(String, fn(Dynamic) -> Result(msg, Nil)),
    on_attribute_change: Dict(String, Decoder(msg)),
  )
}

/// 
/// 
pub type Action(runtime, msg) {
  AddRenderer(Dynamic, fn(Patch(msg)) -> Nil)
  Attrs(List(#(String, Dynamic)))
  Batch(List(msg), Effect(msg))
  Dispatch(msg)
  Emit(String, Json)
  Event(String, Dynamic)
  RemoveRenderer(Dynamic)
  SetSelector(Selector(Action(runtime, msg)))
  Shutdown
}

// ACTOR -----------------------------------------------------------------------

@target(erlang)
///
/// 
pub fn start(
  init: #(model, Effect(msg)),
  update: fn(model, msg) -> #(model, Effect(msg)),
  view: fn(model) -> Element(msg),
  on_attribute_change: Dict(String, Decoder(msg)),
) -> Result(Subject(Action(runtime, msg)), StartError) {
  let timeout = 1000
  let init = fn() {
    let self = process.new_subject()
    let html = view(init.0)
    let handlers = vdom.handlers(html)
    let state =
      State(
        self,
        init.0,
        update,
        view,
        html,
        dict.new(),
        handlers,
        on_attribute_change,
      )
    let selector = process.selecting(process.new_selector(), self, identity)

    run_effects(init.1, self)
    actor.Ready(state, selector)
  }

  actor.start_spec(Spec(init, timeout, loop))
}

@target(erlang)
fn loop(
  message: Action(runtime, msg),
  state: State(runtime, model, msg),
) -> Next(Action(runtime, msg), State(runtime, model, msg)) {
  case message {
    Attrs(attrs) -> {
      list.filter_map(attrs, fn(attr) {
        case dict.get(state.on_attribute_change, attr.0) {
          Error(_) -> Error(Nil)
          Ok(decoder) ->
            decoder(attr.1)
            |> result.replace_error(Nil)
        }
      })
      |> Batch(effect.none())
      |> loop(state)
    }

    AddRenderer(id, renderer) -> {
      let renderers = dict.insert(state.renderers, id, renderer)
      let next = State(..state, renderers: renderers)

      renderer(Init(dict.keys(state.on_attribute_change), state.html))
      actor.continue(next)
    }

    Batch([], _) -> actor.continue(state)
    Batch([msg], other_effects) -> {
      let #(model, effects) = state.update(state.model, msg)
      let html = state.view(model)
      let diff = patch.elements(state.html, html)
      let next =
        State(..state, model: model, html: html, handlers: diff.handlers)

      run_effects(effect.batch([effects, other_effects]), state.self)

      case patch.is_empty_element_diff(diff) {
        True -> Nil
        False -> run_renderers(state.renderers, Diff(diff))
      }

      actor.continue(next)
    }
    Batch([msg, ..rest], other_effects) -> {
      let #(model, effects) = state.update(state.model, msg)
      let html = state.view(model)
      let diff = patch.elements(state.html, html)
      let next =
        State(..state, model: model, html: html, handlers: diff.handlers)

      loop(Batch(rest, effect.batch([effects, other_effects])), next)
    }

    Dispatch(msg) -> {
      let #(model, effects) = state.update(state.model, msg)
      let html = state.view(model)
      let diff = patch.elements(state.html, html)
      let next =
        State(..state, model: model, html: html, handlers: diff.handlers)

      run_effects(effects, state.self)

      case patch.is_empty_element_diff(diff) {
        True -> Nil
        False -> run_renderers(state.renderers, Diff(diff))
      }

      actor.continue(next)
    }

    Emit(name, event) -> {
      let patch = patch.Emit(name, event)

      run_renderers(state.renderers, patch)
      actor.continue(state)
    }

    Event(name, event) -> {
      case dict.get(state.handlers, name) {
        Error(_) -> actor.continue(state)
        Ok(handler) -> {
          handler(event)
          |> result.map(Dispatch)
          |> result.map(actor.send(state.self, _))
          |> result.unwrap(Nil)

          actor.continue(state)
        }
      }
    }

    RemoveRenderer(id) -> {
      let renderers = dict.delete(state.renderers, id)
      let next = State(..state, renderers: renderers)

      actor.continue(next)
    }

    SetSelector(selector) -> actor.Continue(state, Some(selector))
    Shutdown -> actor.Stop(process.Killed)
  }
}

// UTILS -----------------------------------------------------------------------

@target(erlang)
fn run_renderers(
  renderers: Dict(any, fn(Patch(msg)) -> Nil),
  patch: Patch(msg),
) -> Nil {
  use _, _, renderer <- dict.fold(renderers, Nil)
  renderer(patch)
}

@target(erlang)
fn run_effects(effects: Effect(msg), self: Subject(Action(runtime, msg))) -> Nil {
  let dispatch = fn(msg) { actor.send(self, Dispatch(msg)) }
  let emit = fn(name, event) { actor.send(self, Emit(name, event)) }

  effect.perform(effects, dispatch, emit)
}

// Empty implementations of every function in this module are required because we
// need to be able to build the codebase *locally* with the JavaScript target to
// bundle the server component runtime. 
//
// For *consumers* of Lustre this is not a problem, Gleam will see this module is
// never included in any path reachable from JavaScript but when we're *inside the
// package* Gleam has no idea that is the case.

@target(javascript)
pub fn start(
  init: #(model, Effect(msg)),
  update: fn(model, msg) -> #(model, Effect(msg)),
  view: fn(model) -> Element(msg),
  on_attribute_change: Dict(String, Decoder(msg)),
) -> Result(Subject(Action(runtime, msg)), StartError) {
  panic
}

@target(javascript)
fn loop(
  message: Action(runtime, msg),
  state: State(runtime, model, msg),
) -> Next(Action(runtime, msg), State(runtime, model, msg)) {
  panic
}

@target(javascript)
fn run_renderers(
  renderers: Dict(any, fn(Patch(msg)) -> Nil),
  patch: Patch(msg),
) -> Nil {
  panic
}

@target(javascript)
fn run_effects(effects: Effect(msg), self: Subject(Action(runtime, msg))) -> Nil {
  panic
}
