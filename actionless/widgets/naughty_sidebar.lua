--[[
Licensed under GNU General Public License v2
* (c) 2020, Yauheni Kirylau
--]]

local wibox = require('wibox')
local awful = require('awful')
local gears = require('gears')
local beautiful = require('beautiful')
local dpi = beautiful.xresources.apply_dpi

local common = require("actionless.widgets.common")
local db = require("actionless.util.db")


local DB_ID = 'notifications_storage'
local DB_ID_READ_COUNT = 'notifications_storage_read_count'


local pack = table.pack or function(...) -- luacheck: ignore 143
  return { n = select("#", ...), ... }
end


local naughty_sidebar = {
  theme = {
    num_buttons = 2,
  },
}

local function widget_factory(args)
  args	 = args or {}
  args.orientation = args.orientation or "horizontal"
  if (beautiful.panel_widget_spacing ~= nil) and (beautiful.panel_padding_bottom ~= nil) then
    args.padding = {
      left=gears.math.round(beautiful.panel_widget_spacing/2),
      right=math.max(0, gears.math.round(beautiful.panel_widget_spacing/2 + beautiful.panel_padding_bottom) - 1),
    }
    args.margin = {
      left = beautiful.panel_widget_spacing - beautiful.panel_padding_bottom,
      right = beautiful.panel_padding_bottom,
    }
  end
  args.panel_shape = true
  args.fg = args.fg or beautiful.notification_counter_fg
  args.bg = args.bg or beautiful.notification_counter_bg
  args.hide_without_notifications = (args.hide_without_notifications == nil) and true or false

  local set_theme = function(key, ...)
    if naughty_sidebar.theme[key] ~= nil then
      return
    end
    local candidates = pack(...)
    for i=1,candidates.n do
      local candidate = candidates[i]
      if candidate ~= nil then
        naughty_sidebar.theme[key] = candidate
        return
      end
    end
  end

  set_theme('width',
    beautiful.notification_sidebar_width,
    beautiful.notification_max_width,
    dpi(300)
  )
  set_theme('button_padding',
    beautiful.notification_sidebar_button_padding,
    dpi(5)
  )
  set_theme('padding',
    beautiful.notification_sidebar_padding,
    dpi(10)
  )
  set_theme('margin',
    beautiful.notification_sidebar_margin,
    dpi(10)
  )
  set_theme('spacing',
    beautiful.notification_sidebar_spacing,
    dpi(10)
  )
  set_theme('font',
    beautiful.notification_font,
    "Sans 8"
  )
  set_theme('bg',
    beautiful.notification_sidebar_bg,
    beautiful.panel_bg,
    beautiful.bg_normal
  )
  set_theme('fg',
    beautiful.notification_sidebar_fg,
    beautiful.panel_fg,
    beautiful.fg_normal
  )
  set_theme('notification_bg',
    beautiful.notification_bg,
    beautiful.bg_normal
  )
  set_theme('notification_fg',
    beautiful.notification_fg,
    beautiful.fg_normal
  )
  set_theme('notification_border_radius',
    beautiful.notification_border_radius,
    0
  )
  set_theme('notification_border_width',
    beautiful.notification_border_width,
    0
  )
  set_theme('notification_border_color',
    beautiful.notification_border_color,
    beautiful.border_normal
  )
  set_theme('notification_border_color_unread',
    beautiful.warning,
    beautiful.bg_focus
  )
  naughty_sidebar.theme.close_button_size = naughty_sidebar.theme.padding * 2
  naughty_sidebar.theme.button_bg_hover = beautiful.bg_focus
  naughty_sidebar.theme.button_fg_hover = beautiful.fg_focus

  naughty_sidebar.widget = common.decorated(args)
  naughty_sidebar.saved_notifications = db.get_or_set(DB_ID, {})
  naughty_sidebar.prev_count = db.get_or_set(DB_ID_READ_COUNT, 0)
  naughty_sidebar.scroll_offset = 0
  naughty_sidebar._custom_widgets = args.custom_widgets or {}


  function naughty_sidebar:widget_action_button(text, callback, widget_args)
    widget_args = widget_args or {}

    local label = {
      markup = text,
      font = naughty_sidebar.theme.font,
      widget = wibox.widget.textbox,
    }
    if widget_args.align == 'middle' then
      label = {
        nil,
        label,
        nil,
        expand='outside',
        layout = wibox.layout.align.horizontal,
      }
    end
    local widget = common.set_panel_shape(wibox.widget{
      {
        --{
          label,
          --layout = wibox.layout.fixed.vertical,
        --},
        margins = naughty_sidebar.theme.button_padding,
        layout = wibox.container.margin,
      },
      bg = naughty_sidebar.theme.notification_bg,
      fg = naughty_sidebar.theme.notification_fg,
      layout = wibox.container.background,
    })
    widget:buttons(awful.util.table.join(
      awful.button({ }, 1, callback)
    ))
    widget:connect_signal("mouse::enter", function()
      widget.bg = naughty_sidebar.theme.button_bg_hover
      widget.fg = naughty_sidebar.theme.button_fg_hover
    end)
    widget:connect_signal("mouse::leave", function()
      widget.bg = naughty_sidebar.theme.notification_bg
      widget.fg = naughty_sidebar.theme.notification_fg
    end)
    return widget
  end

  function naughty_sidebar:write_notifications_to_db()
    local mini_notifications = {}
    for _, notification in ipairs(self.saved_notifications) do
      local mini_notification = {}
      for _, key in ipairs{'title', 'message', 'icon'} do
        mini_notification[key] = notification[key]
      end
      table.insert(mini_notifications, mini_notification)
    end
    db.set(DB_ID, mini_notifications)
  end

  function naughty_sidebar:update_counter()
    local num_notifications = #naughty_sidebar.saved_notifications
    self.widget:set_text((num_notifications==0) and '' or num_notifications)
    if num_notifications > 0 then
      local unread_count = #self.saved_notifications - self.prev_count
      if unread_count > 0 then
        self.widget:set_warning()
      else
        self.widget:set_normal()
      end
      self.widget:show()
    else
      if args.hide_without_notifications then
        self.widget:hide()
      --else
      --  @TODO: set icon for no notifications
      end
    end
  end

  function naughty_sidebar:remove_notification(idx)
    table.remove(self.saved_notifications, idx)
    self:write_notifications_to_db()
    self:update_counter()
    if #self.saved_notifications > 0 then
      self:refresh_notifications()
    else
      self:toggle_sidebox()
    end
  end

  function naughty_sidebar:remove_all_notifications()
    self.saved_notifications = {}
    self:write_notifications_to_db()
    self:toggle_sidebox()
    self:update_counter()
  end

  function naughty_sidebar:widget_notification(notification, idx, unread)
    notification.args = notification.args or {}
    local actions = wibox.layout.fixed.vertical()
    actions.spacing = gears.math.round(naughty_sidebar.theme.padding * 0.75)

    local close_button = common.panel_shape(wibox.widget{
      {
        nil,
        wibox.widget.textbox('x'),
        nil,
        expand='outside',
        layout = wibox.layout.align.horizontal,
      },
      height = naughty_sidebar.theme.close_button_size,
      width = naughty_sidebar.theme.close_button_size,
      strategy = 'exact',
      layout = wibox.container.constraint,
    })
    close_button.opacity = 0.4

    local widget = wibox.widget{
      {
        {
          {
            wibox.widget.textbox(notification.title),
            nil,
            close_button,
            layout = wibox.layout.align.horizontal
          },
          {
            markup = notification.message,
            font = naughty_sidebar.theme.font,
            widget = wibox.widget.textbox,
          },
          actions,
          layout = wibox.layout.fixed.vertical
        },
        margins = naughty_sidebar.theme.padding,
        layout = wibox.container.margin,
      },
      bg = naughty_sidebar.theme.notification_bg,
      fg = naughty_sidebar.theme.notification_fg,
      shape_clip = true,
      shape = function(c, w, h)
        return gears.shape.rounded_rect(c, w, h, naughty_sidebar.theme.notification_border_radius)
      end,
      shape_border_width = naughty_sidebar.theme.notification_border_width,
      shape_border_color = naughty_sidebar.theme.notification_border_color,
      layout = wibox.container.background,
    }
    if unread then
      widget.border_color = naughty_sidebar.theme.notification_border_color_unread
    end
    widget.lie_idx = idx
    local function default_action()
      notification.args.run(notification)
    end

    local create_buttons_row = function()
      local row = wibox.layout.flex.horizontal()
      row.spacing = actions.spacing
      row.max_widget_size = (
        naughty_sidebar.theme.width -
        naughty_sidebar.theme.margin * 2 -
        naughty_sidebar.theme.padding * 2 -
        actions.spacing * (naughty_sidebar.theme.num_buttons - 1)
      ) / naughty_sidebar.theme.num_buttons
      return row
    end
    local separator_before_actions = common.constraint{height=naughty_sidebar.theme.padding * 0.25}
    local buttons_row = create_buttons_row()
    local num_buttons = 0
    if notification.args.run then
      buttons_row:add(self:widget_action_button('Open', default_action))
      num_buttons = num_buttons + 1
    end
    for _, action in pairs(notification.actions or {}) do
      buttons_row:add(self:widget_action_button(action:get_name(), function()
        action:invoke(notification)
      end))
      num_buttons = num_buttons + 1
      if num_buttons % naughty_sidebar.theme.num_buttons == 0 then
        if num_buttons == naughty_sidebar.theme.num_buttons then
          actions:add(separator_before_actions)
        end
        actions:add(buttons_row)
        buttons_row = create_buttons_row()
      end
    end
    if num_buttons > 0 and num_buttons < naughty_sidebar.theme.num_buttons then
      actions:add(separator_before_actions)
      actions:add(buttons_row)
    end

    close_button:connect_signal("mouse::enter", function()
      close_button.opacity = 1
      close_button.bg = naughty_sidebar.theme.button_bg_hover
      close_button.fg = naughty_sidebar.theme.button_fg_hover
    end)
    close_button:connect_signal("mouse::leave", function()
      close_button.opacity = 0.4
      close_button.bg = naughty_sidebar.theme.notification_bg
      close_button.fg = naughty_sidebar.theme.notification_fg
    end)
    close_button:buttons(awful.util.table.join(
      awful.button({ }, 1, nil, function()
        self:remove_notification(widget.lie_idx)
      end)
    ))
    widget:buttons(awful.util.table.join(
      awful.button({ }, 1, function()
        if notification.args.run then
          default_action()
        end
      end),
      awful.button({ }, 3, function()
        self:remove_notification(widget.lie_idx)
      end)
    ))
    return widget
  end

  function naughty_sidebar:widget_panel_label(text)
    return wibox.widget{
      nil,
      {
        {
          text=text,
          widget=wibox.widget.textbox
        },
        fg=naughty_sidebar.theme.fg,
        layout = wibox.container.background,
      },
      nil,
      expand='outside',
      layout=wibox.layout.align.horizontal,
    }
  end

  function naughty_sidebar:refresh_notifications()
    local layout = wibox.layout.fixed.vertical()
    layout.spacing = naughty_sidebar.theme.spacing
    local margin = wibox.container.margin()
    margin.margins = naughty_sidebar.theme.margin
    for _, widget in ipairs(naughty_sidebar._custom_widgets) do
      layout:add(widget)
    end
    if #self.saved_notifications > 0 then
      layout:add(self:widget_action_button(
        '  X  Clear Notifications  ',
        function()
          self:remove_all_notifications()
        end,
        {align='middle', full_width=true}
      ))
      local unread_count = #self.saved_notifications - self.prev_count
      if self.scroll_offset > 0 then
          --text='^^^',
        layout:add(self:widget_panel_label('↑ ↑'))
      end
      for idx, n in ipairs(naughty_sidebar.saved_notifications) do
        if idx > self.scroll_offset then
          layout:add(
            self:widget_notification(n, idx, idx<=unread_count)
          )
        end
      end
    else
      layout:add(self:widget_panel_label('No notifications'))
    end
    margin:set_widget(layout)
    self.sidebar.bg = naughty_sidebar.theme.bg

    self.sidebar:set_widget(margin)
    self.sidebar.lie_layout = layout
  end

  function naughty_sidebar:mark_all_as_read()
    self.prev_count = #self.saved_notifications
    db.set(DB_ID_READ_COUNT, self.prev_count)
  end

  function naughty_sidebar:remove_unread()
    self.scroll_offset = 0
    self:refresh_notifications()
    local num_notifications = #self.saved_notifications
    if num_notifications > 0 then
      local unread_count = #self.saved_notifications - self.prev_count
      while unread_count > 0 do
        self:remove_notification(1)
        unread_count = unread_count - 1
      end
    end
  end

  function naughty_sidebar:toggle_sidebox()
    if not self.sidebar then
      local workarea = awful.screen.focused().workarea
      self.sidebar = wibox({
        width = naughty_sidebar.theme.width,
        height = workarea.height,
        x = workarea.width - naughty_sidebar.theme.width,
        y = workarea.y,
        ontop = true,
        type='dock',
      })
      self.sidebar:buttons(awful.util.table.join(
        awful.button({ }, 4, function()
          self.scroll_offset = math.max(
            self.scroll_offset - 1, 0
          )
          self:refresh_notifications()
        end),
        awful.button({ }, 5, function()
          self.scroll_offset = math.min(
            self.scroll_offset + 1, #self.saved_notifications - 1
          )
          self:refresh_notifications()
        end)
      ))
      self:refresh_notifications()
    end
    if self.sidebar.visible then
      self.sidebar.visible = false
      self:mark_all_as_read()
    else
      self:refresh_notifications()
      self.sidebar.visible = true
    end
    self.widget:set_normal()
  end

  function naughty_sidebar:add_notification(notification)
    log{
      'notification added',
      notification.title,
      notification.message,
      notification.app_name,
    }
    table.insert(self.saved_notifications, 1, notification)
    self:write_notifications_to_db()
    self:update_counter()
    if self.sidebar and self.sidebar.visible then
      self:refresh_notifications()
    end
  end


  naughty_sidebar.widget:buttons(awful.util.table.join(
    awful.button({ }, 1, function()
      naughty_sidebar:toggle_sidebox()
    end),
    awful.button({ }, 3, function()
      if naughty_sidebar.sidebar and naughty_sidebar.sidebar.visible then
        naughty_sidebar:remove_unread()
        naughty_sidebar.sidebar.visible = false
      else
        naughty_sidebar:mark_all_as_read()
        naughty_sidebar:update_counter()
      end
    end)
  ))

  if beautiful.show_widget_icon and beautiful.widget_notifications then
    naughty_sidebar.widget:set_image(beautiful.widget_notifications)
  else
    naughty_sidebar.widget:hide()
  end
  naughty_sidebar:update_counter()

  return setmetatable(naughty_sidebar, { __index = naughty_sidebar.widget })
end

return setmetatable(naughty_sidebar, { __call = function(_, ...)
  return widget_factory(...)
end })
