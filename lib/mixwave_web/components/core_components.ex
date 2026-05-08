defmodule MixwaveWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  Styling foundation: Tailwind v4 + shadcn-vue's design tokens.
  Semantic Tailwind utilities like `bg-background`, `text-foreground`,
  `border-input`, `bg-primary`, etc. are wired up in `assets/css/app.css`
  and resolve to light/dark CSS variables, so the same classes work
  in both modes.

    * [Tailwind CSS](https://tailwindcss.com)
    * [shadcn-vue](https://shadcn-vue.com) — the Vue components mounted
      inside LiveView islands. The HEEX side uses the same color tokens
      so the design language is consistent across both.
    * [Heroicons](https://heroicons.com) — see `icon/1`.
  """
  use Phoenix.Component
  use Gettext, backend: MixwaveWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="fixed top-4 right-4 z-50 w-80 sm:w-96 max-w-[calc(100vw-2rem)]"
      {@rest}
    >
      <div class={[
        "flex items-start gap-3 rounded-md border p-4 shadow-md text-sm",
        @kind == :info && "border-border bg-card text-card-foreground",
        @kind == :error && "border-destructive/30 bg-destructive/10 text-destructive"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0 mt-0.5" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0 mt-0.5" />
        <div class="flex-1">
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <button type="button" class="opacity-50 hover:opacity-100 cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button. Mirrors shadcn-vue's Button variants on the HEEX side
  so HEEX templates and Vue islands share a visual language.
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any
  attr :variant, :string, values: ~w(primary outline ghost), default: "primary"
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    base =
      "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm " <>
        "font-medium ring-offset-background transition-colors focus-visible:outline-none " <>
        "focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 " <>
        "disabled:pointer-events-none disabled:opacity-50 h-10 px-4 py-2 cursor-pointer"

    variant_classes = %{
      "primary" => "bg-primary text-primary-foreground hover:bg-primary/90",
      "outline" =>
        "border border-input bg-background hover:bg-accent hover:text-accent-foreground",
      "ghost" => "hover:bg-accent hover:text-accent-foreground"
    }

    assigns =
      assign_new(assigns, :class, fn ->
        [base, Map.fetch!(variant_classes, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.
  Same API as the original Phoenix scaffold; styled with shadcn tokens.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="mb-2">
      <label for={@id} class="flex items-center gap-2 text-sm">
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={@class || "size-4 rounded border-input text-primary focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:ring-offset-background"}
          {@rest}
        />{@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="mb-2">
      <label for={@id} class="block">
        <span :if={@label} class="block mb-1.5 text-sm font-medium">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[
            @class || @class || input_classes(),
            @errors != [] && (@error_class || "border-destructive")
          ]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="mb-2">
      <label for={@id} class="block">
        <span :if={@label} class="block mb-1.5 text-sm font-medium">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || textarea_classes(),
            @errors != [] && (@error_class || "border-destructive")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs (text, email, password, etc.) handled here
  def input(assigns) do
    ~H"""
    <div class="mb-2">
      <label for={@id} class="block">
        <span :if={@label} class="block mb-1.5 text-sm font-medium">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || input_classes(),
            @errors != [] && (@error_class || "border-destructive")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  defp input_classes do
    "flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm " <>
      "ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none " <>
      "focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 " <>
      "disabled:cursor-not-allowed disabled:opacity-50"
  end

  defp textarea_classes do
    "flex min-h-[80px] w-full rounded-md border border-input bg-background px-3 py-2 text-sm " <>
      "ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none " <>
      "focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 " <>
      "disabled:cursor-not-allowed disabled:opacity-50"
  end

  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-destructive">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-muted-foreground">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="rounded-md border overflow-hidden">
      <table class="w-full text-sm">
        <thead class="bg-muted/50">
          <tr class="border-b">
            <th :for={col <- @col} class="text-left px-4 py-2 font-medium">{col[:label]}</th>
            <th :if={@action != []} class="w-0 px-4 py-2">
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="border-b last:border-0 even:bg-muted/30">
            <td
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={["px-4 py-3", @row_click && "hover:cursor-pointer"]}
            >
              {render_slot(col, @row_item.(row))}
            </td>
            <td :if={@action != []} class="px-4 py-3 w-0 font-medium">
              <div class="flex gap-4">
                <%= for action <- @action do %>
                  {render_slot(action, @row_item.(row))}
                <% end %>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="divide-y rounded-md border">
      <li :for={item <- @item} class="flex flex-col gap-1 px-4 py-3">
        <div class="font-semibold text-sm">{item.title}</div>
        <div class="text-sm text-muted-foreground">{render_slot(item)}</div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(MixwaveWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(MixwaveWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
