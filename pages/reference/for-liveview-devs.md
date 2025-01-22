# Lustre for LiveView developers

Coming from LiveView, many things about Lustre will feel very familiar. But in many
other ways it will be quite different. This guide is for LiveView developers who
are new to Lustre and want to get up to speed quickly.

## How do I...?

### Setup a new project

**In LiveView** you create a new Phoenix project with `mix phx.new`. A simple
hello world might look like this:

```elixir
 # lib/my_app_web/live/hello_live.ex
 defmodule MyAppWeb.HelloLive do
  use MyAppWeb, :live_view

  def render(assigns) do
    ~H"""
    <h1>Hello, Joe</h1>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, socket}
  end
 end
```

To start your dev server, run `mix phx.start`

---

**In Lustre**, after you've created a new Gleam project with `gleam new`, you need
to install the `lustre` package with `gleam add lustre`. Most Lustre projects will
add the dev tools too with `gleam add --dev lustre_dev_tools`. A simple hello
world might look like this:

```gleam
// main.gleam
import lustre
import lustre/element/html

pub fn main() {
  let app = lustre.element(html.h1([], [html.text("Hello, Joe")]))
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}
```

To start your dev server, run `gleam run -m lustre/dev start`

### Render some HTML

**In LiveView** you use HEEx templates to render HTML elements. This looks like
HTML and allows you to interpolate Elixir code and dynamic values in your template.

```html
<button class="primary">Click me</button>
```

---

**In Lustre** HTML is rendered by calling functions. Usually the first argument
is a list of `Attribute` types, and the second argument a list of `Element` type
children.

```gleam
button([class("primary")], [text("Click me")])
```

### Render some text

**In LiveView** a string is a valid type of node, so you can render text by just
writing it in your HEEx template:

```html
<span>Hello</span>
```

To concatenate text with other variables or expressions, you can use `<%= %>` tags.

```html
<span>Hello <%= @name %></span>
```

---

**In Lustre** because of Gleam's type system, all elements must be Lustre's `Element`
type. To render text you need to use the `text` function:

```gleam
span([], [
  text("Hello"),
  text("Hello" <> name),
])
```

### Manage state

**In LiveView** all your state is stored in the `assigns` key of the socket. Updates
happen by sending events to the LiveView process, where the event handlers will
update the relevant state and return the updated socket.

```elixir
def mount(_params, _session, socket) do
  socket = assign(socket, :value, 1)
  {:ok, socket}
end

def handle_event("increment", _params, socket) do
  {:noreply, update(socket, :value, &(&1 + 1))}
end

def handle_event("decrement", _params, socket) do
  {:noreply, update(socket, :value, &(&1 - 1))}
end
```

---

**In Lustre** all state is stored in a single `Model` type and updates happen
through a central `update` function. A notable difference here is that Gleam does
not allow pattern matching in function heads, so instead you use a `case` statement
to match on the different messages and handle them accordingly.

```gleam
fn init(_) {
  0
}

type Msg {
  Incr
  Decr
}

fn update(model, msg) {
  case msg {
    Incr -> model + 1
    Decr -> model - 1
  }
}
```

### Handle events

**In LiveView** you can bind messages to events in your HEEx template and define
`handle_event/3` functions that receive the event name, any addtional parameters
and the socket. These usually change some kind of state, and return the updated
socket. LiveView provides handlers for most common events and passes the accompanying
values to your event handler.

```html
<button phx-click="decrement">-</button>
```

```html
<input phx-change="update_input"> />
```

With a bit of JavaScript you can also handle events that are not provided in LiveView.

```html
<div id="my-div" phx-hook="MouseMove"></div>
```

```js
let Hooks = {};

Hooks.MouseMove = {
  mounted() {
    this.el.addEventListener("mousemove", e => {
      ...
    })
  }
}
```

---

**In Lustre** event handlers are decoders for event objects. When the decoders
succeeds, that value is passed to your `update` function. Lustre provides functions
to handle most common events.

```gleam
button([on_click(Decr)], [text("-")])
```

```gleam
input([on_input(UpdateInput)])
```

```gleam
div([on("mousemove", fn(event) {
  ...
}], [...])
```

### Write a component

**In LiveView** you can define function components to organise and reuse markup.

```elixir
def render(assigns) do
  ~H"""
    <.greet name={@name} />
  """
end

defp greet(assigns) do
  ~H"""
    <h1>Hello, <%= @name %></h1>
  """
end
```

LiveView also allows for live components that contain state, markup and events,
but Lustre does not have the equivalent of these.

---

**In Lustre** components are more commonly referred to as "view functions". They
are regular Gleam functions.

```gleam
fn greet(name: String) -> Element(Msg) {
  html.h1([], [html.text("Hello, "  <> name)])
}
```

---

### Fetch data

**In LiveView** ...

---

**In Lustre**...

## Where to go next

To walk through setting up a new Lustre project and building your first app, check
out the [quickstart guide](https://hexdocs.pm/lustre/guide/01-quickstart.html).

If you prefer to learn by example, we have a collection of examples that show
off specific features and patterns in Lustre. You can find them in the
[examples directory](https://hexdocs.pm/lustre/reference/examples.html)

If you're having trouble with Lustre or not sure what the right way to do
something is, the best place to get help is the [Gleam Discord server](https://discord.gg/Fm8Pwmy).
You could also open an issue on the [Lustre GitHub repository](https://github.com/lustre-labs/lustre/issues).
