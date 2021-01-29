function string.underscore_name(str)
    str = tostring(str)
    return str:gsub("([^A-Z%W])([A-Z])", "%1%_%2"):gsub("([A-Z]+)([A-Z][^A-Z$])", "%1%_%2"):lower()
end

BLE.Utils = BLE.Utils or {}
local Utils = BLE.Utils

Utils.EditorIcons = {
    ["texture"] = "textures/editor_icons_df",
    ["trash"] = {7, 2, 48, 48},
    ["pen"] = {66, 1, 48, 48},
    ["cross"] = {182, 4, 48, 48},
    ["cross_box"] = {122, 1, 48, 48},
    ["arrow_up"] = {11, 58, 48, 48},
    ["arrow_down"] = {61, 58, 48, 48},
    ["plus"] = {111, 55, 48, 48},
    ["minus"] = {161, 55, 48, 48},
    ["eye"] = {155, 95, 64, 64},
    ["collapse_all"] = {161, 158, 50, 50},
    ["help"] = {8, 149, 64, 64},
    ["alert"] = {107, 181, 64, 64},
    ["settings_gear"] = {385, 385, 115, 115},
}

function Utils:GetIcon(name)
    return Utils.EditorIcons[name]
end

local static
local editor_menu

Utils.LinkTypes = {Unit = 1, Element = 2, Instance = 3}

function Utils:UpdateCollisionsAndVisuals(unit, skip)
    editor_menu = editor_menu or managers.editor._menu
    static = static or self:GetPart("static")

    if not skip and static._widget_hold or editor_menu._slider_hold then
        table.insert(static._ignored_collisions, unit)
    else
        if alive(unit) and unit:enabled() then
            unit:set_enabled(false)
            unit:set_enabled(true)
        end
    end
end

--Sets the position of a unit/object correctly
function Utils:SetPosition(unit, position, rotation, ud, offset)
	ud = ud or unit.unit_data and unit:unit_data()
    unit:set_position(position)
    if rotation then
        unit:set_rotation(rotation)
    end
    if unit.get_objects_by_type then
        static = static or self:GetPart("static")
        local unit_key = unit:key()

        --If you try setting a position through the textbox or even just calling this function the collisions will fail to update for some units.
        --So we added a delayedcall for it, this engine..
        DelayedCalls:Remove(unit_key)
        DelayedCalls:Add(unit_key, 0.01, function()
            self:UpdateCollisionsAndVisuals(unit)
        end)

		if ud then
			ud.position = position
			if rotation then
				ud.rotation = rotation
			end
		end
        local me = unit:mission_element()

        if me then
            static._set_elements[me.element.id] = me
        elseif ud.name and not ud.instance then
            static._set_units[unit_key] = unit
        end
    end
end

function Utils:ParseXml(typ, path, scriptdata, assets_dir)
	-- First try reading from the game's bundles directly, if we're using a version of SBLT that supports it
	if blt.asset_db then
		local raw = blt.asset_db.read_file(path, typ, {
			optional = true
		})
		if raw ~= nil then
			if scriptdata then
				return FileIO:ConvertScriptData(raw, "binary")
			else
				return Node.from_xml(raw)
			end
		end
	end

	local file = Path:Combine(assets_dir or BLE.ExtractDirectory, path.."."..typ)
	local load = function(path)
		if scriptdata then
			return FileIO:ReadScriptData(path, "binary")
		else
			return SystemFS:parse_xml(path, "r")
		end
	end
    if FileIO:Exists(file) then
        return load(file)
	else
        --This is confusing..
        local key_file = Path:Combine(assets_dir or BLE.ExtractDirectory, BLEP.swap_endianness(path:key()).."."..typ)
		if FileIO:Exists(key_file) then
			return load(key_file)
		else
			return nil
        end
    end
end

function Utils:FilterList(a,b)
    local search = b or a
    local label = b and a or nil
    local menu = search.parent
    if type(label) == "table" then
        menu = label
        label = nil
    else
        menu = menu.name == "Toolbar" and menu.parent or menu
    end
    local i = 0
    for _, item in pairs(menu:Items()) do
        local _end = i == max_items
        if type_name(item) == "Button" and (not label or item.label == label) then
            if _end then
                item:SetVisible(false, true, true)
            else
                local search_val = search:Value():escape_special()
                item:SetVisible(search_val == "" or item:Text():find(search_val) ~= nil, true, true)
                i = i + 1
            end
        end
    end
    menu:AlignItems()
end

local mb = 1048576
function Utils:GetPackageSize(package)
    local bundle = "assets/" .. (package:find("/") and package:key() or package) .. ".bundle"
    if FileIO:Exists(bundle) then
        local file = io.open(bundle, "rb")
        if file then
            local size = tonumber(file:seek("end")) / mb
            file:close()
            return size
        else
            return false
        end
    end
end

Utils.allowed_units = {
    ["core/units/effect/effect"] = true,
    ["core/units/nav_surface/nav_surface"] = true,
    ["units/dev_tools/level_tools/ai_coverpoint"] = true,
    ["core/units/environment_area/environment_area"] = true,
    ["core/units/sound_environment/sound_environment"] = true,
    ["core/units/sound_emitter/sound_emitter"] = true,
    ["core/units/sound_area_emitter/sound_area_emitter"] = true,
    ["core/units/cubemap_gizmo/cubemap_gizmo"] = true,
}

function Utils:IsLoaded(asset, type, packages)
    if self.allowed_units[asset] then
        return true
    end
    for name, package in pairs(packages or BLE.DBPackages) do
        if not name:match("all_") and package[type] and package[type][asset] then
            return true
        end
    end
    return false
end

function Utils:GetPackagesOfUnit(unit, size_needed, packages, first)
    return self:GetPackages(unit, "unit", size_needed, first, packages)
end

function Utils:GetPackages(asset, type, size_needed, first, packages)
    local found_packages = {}
    for name, package in pairs(packages or BLE.DBPackages) do
        if not name:begins("all_") and package[type] and package[type][asset] then
            local custom = CustomPackageManager.custom_packages[name:key()] ~= nil
            local package_size = not custom and size_needed and self:GetPackageSize(name)
            if not size_needed or package_size or custom then
                if not name:begins("all_") then
                    table.insert(found_packages, {name = name, package_size = package_size, custom = custom})
                    if first then
                        return found_packages
                    end
                end
            end
        end
    end
    return found_packages
end

function Utils:GetAllLights()
	local lights = {}
	local all_units = World:find_units_quick("all")
	for _,unit in ipairs( all_units ) do
		for _,light in ipairs( unit:get_objects_by_type( Idstring( "light" ) ) ) do
			table.insert( lights, light )
		end
	end	
	return lights
end

function Utils:HasEditableLights(unit)
    local lights = self:GetLights(unit)
    return lights and #lights > 0
end

function Utils:GetLights(unit)
    if not unit.get_objects_by_type then
        return nil
    end
    local has_lights = #unit:get_objects_by_type(Idstring("light")) > 0
    if not has_lights then
        return nil
    end
    local lights = {}
    local node = self:ParseXml("object", unit:unit_data().name)
    if node then
        for child in node:children() do
            if child:name() == "lights" then
                for light in child:children() do
                    local object = unit:get_object(Idstring(light:parameter("name")))
                    if alive(object) and light:has_parameter("editable") and light:parameter("editable") == "true" then
                        table.insert(lights, {name = light:parameter("name"), object = object})
                    end
                end
            end
        end
    end
    return lights
end

local vals = {}
for _, intensity in ipairs(LightIntensityDB:list()) do
    table.insert(vals, LightIntensityDB:lookup(intensity))
end
table.sort(vals)
Utils.IntensityValues = vals
Utils.IntensityOptions = {
    "none",
    "identity",
    "match",
    "candle",
    "desklight",
    "neonsign",
    "flashlight",
    "monitor",
    "dimilight",
    "streetlight",
    "searchlight",
    "reddot",
    "sun",
    "inside of borg queen",
    "megatron"
}

local intensities = {}
for _, v in pairs(Utils.IntensityOptions) do
    intensities[v:id():t()] = v
end

local ids = getmetatable(Idstring())
function ids:s()
    local t = self:t()
    return managers.editor and managers.editor._idstrings[t] or intensities[t] or t
end


function ids:construct(id)
    local xml = ScriptSerializer:from_custom_xml(string.format('<table type="table" id="@ID%s@">', id))
    return xml and xml.id or nil
end

function Utils:GetIntensityPreset(multiplier)
    local intensity = LightIntensityDB:reverse_lookup(multiplier)
    if intensity ~= Idstring("undefined") then
        return intensity
    end
    local values = self.IntensityValues
    for i = 1, #values do
        local next = values[i + 1]
        local this = values[i]
        if not next then
            return LightIntensityDB:reverse_lookup(this)
        end
        if multiplier > this and multiplier < next then
            if multiplier - this < next - multiplier then
                return LightIntensityDB:reverse_lookup(this)
            else
                return LightIntensityDB:reverse_lookup(next)
            end
        elseif multiplier < this then
            return LightIntensityDB:reverse_lookup(this)
        end
    end
end

function Utils:LightData(unit)
    local lights = self:GetLights(unit)
    if not lights then
        return nil
    end
    local t = {}
    for _, light in pairs(lights) do
        local obj = light.object
        local intensity_ids = self:GetIntensityPreset(obj:multiplier())
        local intensity = "undefined"
        for _, v in pairs(self.IntensityOptions) do
            if v:id() == intensity_ids then
                intensity = v
            end
        end
        table.insert(t, {
            name = light.name,
            enabled = obj:enable(),
            far_range = obj:far_range(),
            near_range = obj:near_range(),
            color = obj:color(),
            spot_angle_start = obj:spot_angle_start(),
            spot_angle_end = obj:spot_angle_end(),
            multiplier = intensity,
            falloff_exponent = obj:falloff_exponent(),
            clipping_values = obj:clipping_values()
        })
    end
    return #t > 0 and t or nil
end

function Utils:HasAnyProjectionLight(unit)
    if not unit.get_objects_by_type then
        return
    end
    local has_lights = #unit:get_objects_by_type(Idstring("light")) > 0
    if not has_lights then
        return nil
    end
    return self:HasProjectionLight(unit, "shadow_projection") or self:HasProjectionLight(unit, "projection")
end

function Utils:HasProjectionLight(unit, type)
    type = type or "projection"
    local node = self:ParseXml("object", unit:unit_data().name)
    if node then
        for child in node:children() do
            if child:name() == "lights" then
                for light in child:children() do
                    if light:has_parameter(type) and light:parameter(type) == "true" then
                        return light:parameter("name")
                    end
                end
            end
        end
    end
    return nil
end

function Utils:IsProjectionLight(unit, light, type)
    type = type or "projection"
    local node = self:ParseXml("object", unit:unit_data().name)
    if node then
        for child in node:children() do
            if child:name() == "lights" then
                for light_node in child:children() do
                    if light_node:has_parameter(type) and light_node:parameter(type) == "true" and light:name() == Idstring(light_node:parameter("name")) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

function Utils:TriggersData(unit)
    local triggers = managers.sequence:get_trigger_list(unit:name())
    if #triggers == 0 then
        return nil
    end
    local t = {}
    if #triggers > 0 and unit:damage() then
        local trigger_name_list = unit:damage():get_trigger_name_list()
        if trigger_name_list then
            for _, trigger_name in ipairs(trigger_name_list) do
                local trigger_data = unit:damage():get_trigger_data_list(trigger_name)
                if trigger_data and #trigger_data > 0 then
                    for _, data in ipairs(trigger_data) do
                        if alive(data.notify_unit) then
                            table.insert(t, {
                                name = data.trigger_name,
                                id = data.id,
                                notify_unit_id = data.notify_unit:unit_data().unit_id,
                                time = data.time,
                                notify_unit_sequence = data.notify_unit_sequence
                            })
                        end
                    end
                end
            end
        end
    end
    return #t > 0 and t or nil
end

function Utils:EditableGuiData(unit)
    local t
    if unit:editable_gui() then
        t = {
            text = unit:editable_gui():text(),
            font_color = unit:editable_gui():font_color(),
            font_size = unit:editable_gui():font_size(),
            font = unit:editable_gui():font(),
            align = unit:editable_gui():align(),
            vertical = unit:editable_gui():vertical(),
            blend_mode = unit:editable_gui():blend_mode(),
            render_template = unit:editable_gui():render_template(),
            wrap = unit:editable_gui():wrap(),
            word_wrap = unit:editable_gui():word_wrap(),
            alpha = unit:editable_gui():alpha(),
            shape = unit:editable_gui():shape()
        }
    end
    return t
end

function Utils:LadderData(unit)
    local t
    if unit:ladder() then
        t = {
            width = unit:ladder():width(),
            height = unit:ladder():height()
        }
    end
    return t
end

function Utils:ZiplineData(unit)
    local t
	if unit:zipline() then
        t = {
            end_pos = unit:zipline():end_pos(),
            speed = unit:zipline():speed(),
            slack = unit:zipline():slack(),
            usage_type = unit:zipline():usage_type(),
            ai_ignores_bag = unit:zipline():ai_ignores_bag()
        }
    end
    return t
end

function Utils:CubemapData(unit)
    local t
    local cubemap_gizmo = "core/units/cubemap_gizmo/cubemap_gizmo"
    if unit:name() == cubemap_gizmo:id() then
        t = {
            cubemap_resolution = unit:unit_data().cubemap_resolution,
            cubemap_fake_light = unit:unit_data().cubemap_fake_light
        }
    end
    return t
end

function Utils:InSlot(unit, slot)
    local ud = PackageManager:unit_data(Idstring(unit):id())
    if ud then
        local unit_slot = ud:slot()
        for slot in string.gmatch(tostring(slot), "%d+") do
            if tonumber(slot) == unit_slot then
                return true
            end
        end
    end        
    return false
end

function Utils:GetEntries(params)
    local entries = {}
    local IsLoaded

    if params.packages then
        local type, packages = params.type, params.packages
        IsLoaded = function(entry) return self:IsLoaded(entry, type, packages) end
    else
        local ids_type = params.type:id()
        IsLoaded = function(entry) return PackageManager:has(ids_type, entry:id()) end
    end

    for entry in pairs(BLE.DBPaths[params.type]) do
        if (not params.loaded or IsLoaded(entry)) and (not params.check or params.check(entry)) then
            if not params.match or string.find(entry, params.match) ~= nil then
                table.insert(entries, filenames and Path:GetFileName(entry) or entry)
            end
        end
    end
    return entries
end

function Utils:ShortPath(path, times)
    times = times or 3
    local path_splt = string.split(path, "/")
    for i=1, #path_splt - times do table.remove(path_splt, 1) end
    path = "..."
    for _, s in pairs(path_splt) do
        path = path.."/"..s
    end
    return path
end

--Any unit that exists only in editor(except mission element units)
function Utils:GetUnits(params)
    local units = {}
    local unloaded_units = {}
    local unit_ids = Idstring("unit")
    local check = params.check
    local slot = params.slot
    local not_in_slot = params.not_in_slot
    local not_loaded = params.not_loaded
    local packages = params.packages
    local pack_unloaded = params.pack_unloaded
    local loaded_units = {}
    if packages then
        for _, package in pairs(packages) do
            if package.unit then
                for unit in pairs(package.unit) do
                    loaded_units[unit] = true
                end
            end
        end
    end
	local type = params.type
    local not_types = params.not_types
    for unit in pairs(BLE.DBPaths.unit) do
		local slot_fine = not slot or self:InSlot(unit, slot)
		slot_fine = slot_fine and not not_in_slot or not self:InSlot(unit, not_in_slot)
        local unit_fine = (not check or check(unit))
        local unit_type = self:GetUnitType(unit)
        local type_fine = (not type or unit_type == Idstring(type)) and (not not_types or not table.contains(not_types, unit_type))
		local unit_loaded = params.not_loaded or self.allowed_units[unit]
        if not unit_loaded then
            if packages then
                unit_loaded = loaded_units[unit] == true
            else
                unit_loaded = PackageManager:has(unit_ids, unit:id())
			end
		end
        if unit_type and unit_fine and slot_fine and unit_loaded and type_fine then
			table.insert(units, unit)
        end
        if pack_unloaded and not unit_loaded then
            table.insert(unloaded_units, unit)
        end
    end
    return units, unloaded_units
end

function Utils:GetUnitType(unit)
    if not unit then
        log(debug.traceback())
        return Idstring("none")
	end
    local ud = PackageManager:unit_data(Idstring(unit):id())
    return ud and ud:type() 
end

function Utils:Unhash(ids, type)
    for path in pairs(BLE.DBPaths[type or "other"]) do
        if Idstring(path) == ids then
            return path
        end
    end
    return ids:key()
end

function Utils:Notify(title, msg, clbk)
    BLE.Dialog:Show({title = title, message = msg, callback = clbk, force = true})
end

function Utils:YesNoQuestion(msg, clbk, no_clbk)
    self:QuickDialog({title = "Are you sure you want to continue?", message = msg, no = false, force = true}, {{"Yes", clbk}, {"No", no_clbk, no_clbk and true}})
end

function Utils:QuickDialog(opt, items)
    QuickDialog(table.merge({dialog = BLE.Dialog, no = "No"}, opt), items)
end

function Utils:ReadConfig(file)
    return FileIO:ReadScriptData(file, "custom_xml", true)
end

FakeObject = FakeObject or class()
function FakeObject:init(o, unit_data)
    self._fake = true
    self._unit_data = unit_data or {}
    self._o = o
    self._unit_data.positon = self:position()
    self._unit_data.rotation = self:rotation()
end

function FakeObject:set_position(pos)
    if self:alive() then
        if type(self._o.position) == "function" then
            self._o:set_position(pos)
        else
            self._o.position = pos
        end
    end
end

function FakeObject:set_rotation(rot)
    if self:alive() then
        if type(self._o.rotation) == "function" then
            self._o:set_rotation(rot)
        else
            self._o.rotation = rot
        end
    end
end

function FakeObject:rotation() return self:alive() and type(self._o.rotation) == "function" and self._o:rotation() or self._o.rotation end
function FakeObject:position() return self:alive() and type(self._o.position) == "function" and self._o:position() or self._o.position end
function FakeObject:alive() return self._o and not self._o.alive and true or self._o:alive() end
function FakeObject:enabled() return true end
function FakeObject:fake() return self._fake end
function FakeObject:object() return self._o end
function FakeObject:unit_data() return self._unit_data end
function FakeObject:mission_element() return nil end
function FakeObject:wire_data() return nil end
function FakeObject:ai_editor_data() return nil end
function FakeObject:editable_gui() return nil end
function FakeObject:zipline() return nil end
function FakeObject:ladder() return nil end
function FakeObject:name() return Idstring("blank") end

function Utils:GetPart(name)
    return managers.editor.parts[name]
end

function Utils:GetLayer(name)
    return self:GetPart("world").layers[name]
end

function Utils:GetConvertedResolution()
    return {width = managers.gui_data:full_1280_size().width, height = managers.gui_data:full_1280_size().height}
end

DummyItem = DummyItem or class()
function DummyItem:init(name, v)
	self.name = name
	self.value = v
end
function DummyItem:Value()
	return self.value
end
function DummyItem:SetValue(v)
	self.value = v
end