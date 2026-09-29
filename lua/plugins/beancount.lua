return {
  {
    "hxueh/beancount.nvim",
    ft = { "beancount", "bean" },
    opts = {
      python_path = "python3",
    },
    dependencies = {
      {
        "saghen/blink.cmp",
        opts = function(_, opts)
          opts.sources.default = vim.list_extend(opts.sources.default, { "beancount" })
          opts.sources.providers = opts.sources.providers or {}
          opts.sources.providers.beancount = {
            name = "beancount",
            module = "beancount.completion.blink",
            score_offset = 100,
            opts = {
              trigger_characters = { ":", "#", "^", '"', " " },
            },
          }
          return opts
        end,
      },
      { "L3MON4D3/LuaSnip", optional = true },
    },
    config = function(_, opts)
      require("beancount").setup(opts)
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      vim.list_extend(opts.ensure_installed, { "beancount" })
    end,
  },
}
