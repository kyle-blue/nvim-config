if not vim.g.vscode then
	return
end

local function vsc(action)
	return function()
		vim.fn.VSCodeNotify(action)
	end
end

vim.keymap.set("n", "<leader>sf", vsc("workbench.action.quickOpen"))
vim.keymap.set("n", "<leader>sg", vsc("workbench.action.findInFiles"))
vim.keymap.set("n", "<leader>f", vsc("editor.action.formatDocument"))
vim.keymap.set("n", "<leader>q", vsc("workbench.actions.view.problems"))
