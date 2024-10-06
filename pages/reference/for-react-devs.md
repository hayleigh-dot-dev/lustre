# Lustre for React developers

In some ways React and Lustre share the same DNA. But in a lot of other ways they
can be quite different! This guide is for React developers who are new to Lustre
and want to get up to speed quickly.

## How do I...?

### Setup a new project

**In React** you are encouraged to use a meta framework like Next.js or Remix. To
start a barebones project you need to run `npm install react react-dom`. You will
typically use a bundler that can transpile JSX like `npm install --save-dev vite`.
Many modern projects use TypeScript as well: `npm install --save-dev typescript`.
A simple hello world might look like this:

```jsx
// src/index.js
import { createRoot } from "react-dom/client";

const root = createRoot(document.getElementById("app"));

root.render(<h1>Hello, world</h1>);
```

To run the project you could use Vite's development server with `npx vite`.

---

**In Lustre** you need to install the `lustre` package with `gleam add lustre`.
Most Lustre projects will add the dev tools too with `gleam add --dev lustre_dev_tools`.
A simple hello world might look like this:

```gleam
// main.gleam
import lustre
import lustre/element/html

pub fn main() {
  let app = lustre.element(html.h1([], [html.text("Hello, world")]))
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}
```

### Render some HTML

**In React** you can use JSX to render HTML elements. JSX is a syntax extension
for JavaScript that looks like HTML that lets you interpolate JavaScript expressions
into your markup. Here's an example:

```jsx
<button className="primary">Click me</button>
```

---

**In Lustre** HTML is rendered by calling functions (this is what JSX compiles to
as well).

```gleam
button([class("primary")], [text("Click me")])
```

### Render some text

**In React** a string is a valid type of React node, so you can render text by
just writing it in your JSX:

```jsx
<span>Hello</span>
```

To concatenate text with other variables or expressions, you can use curly braces:

```jsx
<span>Hello {name}</span>
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

**In React** you have many options for state management. Hooks like `useState` and
`useReducer`, context, or libraries like Zustand or Redux are all viable choices.

```jsx
const [count, setCount] = useState(0);
const incr = () => setCount(count + 1);
const decr = () => setCount(count - 1);
```

```jsx
const [state, dispatch] = useReducer((state, action) => {
  switch (action.type) {
    case "increment":
      return state + 1;
    case "decrement":
      return state - 1;
    default:
      return state;
  }
}, 0);
```

---

**In Lustre** all state is stored in a single `Model` type and updates happen
through a central `update` function much like Redux, `useReducer`, or `Elm`.

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

We also need to update our main function to include `init` and `update`, as well as moving our `view` code.

```gleam
fn view() {
  html.h1([], [html.text("Hello, world")])
}

pub fn main() {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}
```

> More on `lustre.simple` later.

You can read more about this approach in the [state management guide](https://hexdocs.pm/lustre/guide/02-state-management.html).

### Handle events

**In React** event handlers are functions that receive an event object and can
do anything you want. Event handlers are not expected to return a value, and
instead typically call `setState` or other side-effecting functions.

```jsx
<button onClick={() => dispatch({ type: "decrement" })}>-</button>
```

```jsx
<input onChange={(event) => setInput(event.target.value)} />
```

```jsx
<div onMouseMove={(event) => {
  ...
}}/>
```

---

**In Lustre** event handlers decoders for event objects. When the decoder succeeds,
that value is passed to your `update` function. Lustre provides functions to handle
most common events:

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

This might seem very familiar, if you've used Redux heavily. A lot of React devs
have scars from those days and tend to dislike anything similar. Don't worry!
Gleam takes inspiration from Elm, which is what originally inspired Redux.

You might have noticed lustre already has a lot less Boilerplate, which is the
first big complaint of redux. The second being lack of built in support for
async, which we'll see is a key part of Lustre (and Elm).

### Write a component

**In React** components are functions that take a single `props` argument and
return a React element. Inside a component, hooks like `useState` and `useEffect`
can be used to manage state and side effects.

```jsx
function Counter({ initialCount }) {
  const [count, setCount] = useState(initialCount);

  return <button onClick={() => setCount(count + 1)}>{count}</button>;
}
```

---

**In Lustre** components are more commonly referred to as "view functions". They
are regular Gleam functions.

```gleam
fn view(model) {
  let count = int.to_string(model)
  button([on_click(Incr)], [text(count)])
}
```

Generally, in lustre you'll just use "view functions" which similar to writing
React components without any hooks and thus no side effect. Luster does have a
primitive, [lustre.component](https://hexdocs.pm/lustre/lustre.html#component),
for cases where local state is needed, but they're a lot heavier compared to
components in React. Avoid using them for things like buttons but things like
comboboxes with complex keyboard interractions is a good use case.

### Fetch data

**In React** the simplest example of data fetching is done with a useEffect.
This will run our fetch once, after the page has rendered, then once we get a
response we store it in a useState which triggers a new render.

```jsx
const [ip, setIp] = useState();

useEffect(() => {
  fetch("https://api.ipify.org")
    .then((response) => response.text())
    .then((data) => setIp(data));
}, []);
```

---

**In Lustre** the higher level process is pretty similar, but since we don't have
local state in lustre we also don't have a way to manage effects locally. We need to
pull the effects up to our update & init functions.

The first thing we need to do is change out the [simple app contructor](https://hexdocs.pm/lustre/lustre.html#simple)
for the final [application constructor](https://hexdocs.pm/lustre/lustre.html#application) which supports side effects.

```gleam
pub fn main() {
  // Change lustre.simple -> lustre.application
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
}
```

Next we're going to add `lustre_http` to our project, which handles creating
effects from network requests for us. (more on creating [your own effects here](https://hexdocs.pm/lustre/guide/03-side-effects.html))

```bash
gleam add lustre_http
```

```gleam
pub type Msg {
  ApiReturnedIpAddress(Result(String, lustre_http.HttpError))
}

fn init(_flags) {
  let model = Model(...)
  let get_ip = lustre_http.get(
    "https://api.ipify.org",
    ApiReturnedIpAddress
  )

  #(model, get_ip)
}

// If you're new to Gleam, this double "Model" might seem strange. Just think of the inner Model as the "Default variant".
pub type Model {
  Model(ip_address: Result(String, HttpError))
}

pub fn update(model, msg) {
  case msg {
    ApiReturnedIpAddress(ip) -> #(Model(..model, ip_address: ip), effect.none())
  }
}


```

You can read more about effects in the [side effects guide](https://hexdocs.pm/lustre/guide/03-side-effects.html).

## Where to go next

To walk through setting up a new Lustre project and building your first app, check
out the [quickstart guide](https://hexdocs.pm/lustre/guide/01-quickstart.html).

If you prefer to learn by example, we have a collection of examples that show
off specific features and patterns in Lustre. You can find them in the
[examples directory](https://hexdocs.pm/lustre/reference/examples.html)

If you're having trouble with Lustre or not sure what the right way to do
something is, the best place to get help is the [Gleam Discord server](https://discord.gg/Fm8Pwmy).
You could also open an issue on the [Lustre GitHub repository](https://github.com/lustre-labs/lustre/issues).
