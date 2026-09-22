vim.filetype.add({
	pattern = {
		[".*Fastfile"] = "ruby",
		[".*Appfile"] = "ruby",
		[".*Matchfile"] = "ruby",
		[".*Pluginfile"] = "ruby",
		-- Angular templates; returning nil falls through to normal html detection
		[".*%.html"] = {
			function(path)
				if require("angular").root(path) then
					return "htmlangular"
				end
			end,
			{ priority = 10 },
		},
	},
})
