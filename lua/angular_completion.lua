-- blink.cmp source offering Angular lifecycle hooks inside component/directive class bodies.
-- Accepting a hook also adds its interface to `implements` and to the @angular/core import.
local source = {}

local DOCS_URL = "https://angular.dev/guide/components/lifecycle#"

local hooks = {
	{
		name = "ngOnChanges",
		interface = "OnChanges",
		imports = { "OnChanges", "SimpleChanges" },
		body = "ngOnChanges(changes: SimpleChanges): void {\n\t$0\n}",
		phase = "Change detection · runs on every input change",
		doc = [[
Runs every time the component's **inputs** have changed, before the view is checked.
On first render it runs before `ngOnInit`.

`changes` maps each changed input name to a `SimpleChange` with `previousValue`,
`currentValue` and `firstChange`.

Not called for inputs changed outside a template binding (e.g. set directly in code).
With signal inputs (`input()`), prefer `computed()` or `effect()` instead.]],
		example = [[
ngOnChanges(changes: SimpleChanges): void {
  if (changes['userId'] && !changes['userId'].firstChange) {
    this.load(changes['userId'].currentValue);
  }
}]],
	},
	{
		name = "ngOnInit",
		interface = "OnInit",
		body = "ngOnInit(): void {\n\t$0\n}",
		phase = "Creation · runs once",
		doc = [[
Runs **once**, after Angular has initialised all of the component's inputs and before
its template is first checked.

Use it for set-up that depends on input values (which are not yet set in the
constructor), such as fetching initial data.]],
		example = [[
ngOnInit(): void {
  this.user$ = this.users.getById(this.userId);
}]],
	},
	{
		name = "ngDoCheck",
		interface = "DoCheck",
		body = "ngDoCheck(): void {\n\t$0\n}",
		phase = "Change detection · runs on every check",
		doc = [[
Runs **every time** Angular checks this component's template for changes.

Lets you implement custom change detection (e.g. detecting mutations Angular can't see),
but it runs extremely often and can hurt performance. Prefer `ngOnChanges` or signals
where possible, and keep the body trivial.]],
		example = [[
ngDoCheck(): void {
  const changes = this.differ.diff(this.items);
  if (changes) this.onItemsMutated(changes);
}]],
	},
	{
		name = "ngAfterContentInit",
		interface = "AfterContentInit",
		body = "ngAfterContentInit(): void {\n\t$0\n}",
		phase = "Creation · runs once",
		doc = [[
Runs **once**, after all children nested inside the component's tags (its projected
`<ng-content>`) have been initialised.

Content queries (`contentChild()`, `contentChildren()`, `@ContentChild`) are resolved here.
Changing state that the template binds to here causes
`ExpressionChangedAfterItHasBeenCheckedError`.]],
		example = [[
ngAfterContentInit(): void {
  this.activeTab ??= this.tabs.first;
}]],
	},
	{
		name = "ngAfterContentChecked",
		interface = "AfterContentChecked",
		body = "ngAfterContentChecked(): void {\n\t$0\n}",
		phase = "Change detection · runs on every check",
		doc = [[
Runs **every time** the component's projected content has been checked for changes.

Runs very frequently; keep it cheap. Changing template-bound state here causes
`ExpressionChangedAfterItHasBeenCheckedError`.]],
	},
	{
		name = "ngAfterViewInit",
		interface = "AfterViewInit",
		body = "ngAfterViewInit(): void {\n\t$0\n}",
		phase = "Creation · runs once",
		doc = [[
Runs **once**, after the component's own template and all of its child views have been
initialised.

View queries (`viewChild()`, `viewChildren()`, `@ViewChild`) are resolved here, so this is
where you can first touch those elements/components. Changing template-bound state here
causes `ExpressionChangedAfterItHasBeenCheckedError`.

For direct DOM work (measuring, third-party libraries), `afterNextRender()` is often the
better fit.]],
		example = [[
ngAfterViewInit(): void {
  this.chart = new Chart(this.canvas.nativeElement, this.config);
}]],
	},
	{
		name = "ngAfterViewChecked",
		interface = "AfterViewChecked",
		body = "ngAfterViewChecked(): void {\n\t$0\n}",
		phase = "Change detection · runs on every check",
		doc = [[
Runs **every time** the component's template and child views have been checked for changes.

Runs very frequently; keep it cheap. For DOM reads/writes after rendering, prefer
`afterEveryRender()`.]],
	},
	{
		name = "ngOnDestroy",
		interface = "OnDestroy",
		body = "ngOnDestroy(): void {\n\t$0\n}",
		phase = "Destruction · runs once",
		doc = [[
Runs **once**, just before Angular destroys the component (or directive, service, pipe).

Clean up anything that would otherwise leak: subscriptions, timers, event listeners,
third-party instances.

Alternatives: `inject(DestroyRef).onDestroy(fn)` or RxJS `takeUntilDestroyed()`.]],
		example = [[
ngOnDestroy(): void {
  this.subscription.unsubscribe();
  clearInterval(this.timer);
}]],
	},
}

local function documentation(hook)
	local parts = { "**" .. hook.name .. "** — `" .. hook.interface .. "`", "_" .. hook.phase .. "_", vim.trim(hook.doc) }
	if hook.example then
		table.insert(parts, "```typescript\n" .. hook.example .. "\n```")
	end
	table.insert(parts, "[Angular docs](" .. DOCS_URL .. hook.name:lower() .. ")")
	return table.concat(parts, "\n\n")
end

local function node_text(node, bufnr)
	return vim.treesitter.get_node_text(node, bufnr)
end

-- Nodes that mean the cursor is inside a member's body/value rather than the class body itself
local not_member_position = {
	statement_block = true,
	object = true,
	arguments = true,
	formal_parameters = true,
	type_annotation = true,
	template_string = true,
	string = true,
	comment = true,
	decorator = true,
}

local function enclosing_class_body(bufnr, row, col)
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "typescript")
	if not ok or not parser then
		return nil
	end
	parser:parse()
	local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { row, math.max(col - 1, 0) }, ignore_injections = true })
	while node do
		local type = node:type()
		if type == "class_body" then
			return node
		end
		if not_member_position[type] then
			return nil
		end
		node = node:parent()
	end
end

local function defined_methods(class_body, bufnr)
	local names = {}
	for child in class_body:iter_children() do
		if child:type() == "method_definition" then
			local name = child:field("name")[1]
			if name then
				names[node_text(name, bufnr)] = true
			end
		end
	end
	return names
end

local function range_at(row, col)
	return { start = { line = row, character = col }, ["end"] = { line = row, character = col } }
end

local function implements_edit(class_node, interface, bufnr)
	local heritage, name
	for child in class_node:iter_children() do
		if child:type() == "class_heritage" then
			heritage = child
		elseif child:type() == "type_identifier" then
			name = child
		end
	end

	if heritage then
		for clause in heritage:iter_children() do
			if clause:type() == "implements_clause" then
				for type in clause:iter_children() do
					if type:named() and node_text(type, bufnr) == interface then
						return nil
					end
				end
				local _, _, er, ec = clause:range()
				return { range = range_at(er, ec), newText = ", " .. interface }
			end
		end
		local _, _, er, ec = heritage:range()
		return { range = range_at(er, ec), newText = " implements " .. interface }
	end

	-- Also covers generic classes, where type_parameters follow the name
	local anchor = class_node:field("type_parameters")[1] or name
	if not anchor then
		return nil
	end
	local _, _, er, ec = anchor:range()
	return { range = range_at(er, ec), newText = " implements " .. interface }
end

local function import_edit(root, names, bufnr)
	local imported = {}
	local named_imports
	for stmt in root:iter_children() do
		if stmt:type() == "import_statement" then
			local src = stmt:field("source")[1]
			local from_core = src and node_text(src, bufnr):match("^['\"]@angular/core['\"]$")
			for clause in stmt:iter_children() do
				if clause:type() == "import_clause" then
					for named in clause:iter_children() do
						if named:type() == "named_imports" then
							if from_core then
								named_imports = named_imports or named
							end
							for spec in named:iter_children() do
								if spec:type() == "import_specifier" then
									local alias = spec:field("alias")[1] or spec:field("name")[1]
									imported[node_text(alias, bufnr)] = true
								end
							end
						end
					end
				end
			end
		end
	end

	local to_add = vim.tbl_filter(function(n)
		return not imported[n]
	end, names)
	if #to_add == 0 then
		return nil
	end

	if named_imports then
		local last
		for spec in named_imports:iter_children() do
			if spec:type() == "import_specifier" then
				last = spec
			end
		end
		if last then
			local _, _, er, ec = last:range()
			return { range = range_at(er, ec), newText = ", " .. table.concat(to_add, ", ") }
		end
	end
	return {
		range = range_at(0, 0),
		newText = "import { " .. table.concat(to_add, ", ") .. " } from '@angular/core';\n",
	}
end

function source.new()
	return setmetatable({}, { __index = source })
end

function source:enabled()
	return vim.bo.filetype == "typescript" and require("angular").root(vim.api.nvim_buf_get_name(0)) ~= nil
end

function source:get_completions(context, callback)
	local bufnr = context.bufnr
	local row, col = context.cursor[1] - 1, context.cursor[2]
	local class_body = enclosing_class_body(bufnr, row, col)
	if not class_body then
		callback({ items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
		return
	end

	local class_node = class_body:parent()
	local root = class_body:tree():root()
	local existing = defined_methods(class_body, bufnr)
	local kind = require("blink.cmp.types").CompletionItemKind.Method

	local items = {}
	for i, hook in ipairs(hooks) do
		if not existing[hook.name] then
			local edits = {}
			table.insert(edits, implements_edit(class_node, hook.interface, bufnr))
			table.insert(edits, import_edit(root, hook.imports or { hook.interface }, bufnr))
			table.insert(items, {
				label = hook.name,
				kind = kind,
				labelDetails = { description = "Angular " .. hook.interface },
				filterText = hook.name,
				sortText = string.format("%02d", i),
				insertText = hook.body,
				insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet,
				additionalTextEdits = edits,
				documentation = { kind = "markdown", value = documentation(hook) },
			})
		end
	end

	callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
end

return source
