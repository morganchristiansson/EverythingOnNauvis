data:extend({
    {
        type = "bool-setting",
        name = "eon-keep-space-platform-restrictions",
        setting_type = "startup",
        default_value = false,
        order = "a"
    },
    {
        type = "int-setting",
        name = "eon-gleba-south-offset",
        setting_type = "startup",
        default_value = 1000,
        minimum_value = 0,
        maximum_value = 10000,
        order = "b"
    },
    {
        type = "double-setting",
        name = "eon-gleba-deep-south-cap",
        setting_type = "startup",
        default_value = 1,
        minimum_value = -3,
        maximum_value = 5,
        order = "c"
    },
    {
        type = "bool-setting",
        name = "eon-holmium-ore",
        setting_type = "startup",
        default_value = true,
        order = "d"
    }
})
