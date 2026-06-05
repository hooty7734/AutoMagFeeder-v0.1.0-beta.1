-- Auto-converted from LEGACY plan: (T4)(S3.9)MIND-5.00-0.00-50.00-44.90-Leilla.Pilla.Mylla-1mf-RareS4-G-Pu-O.mag
-- Feeding fields (item/count/class/section/target_mag) are EXACT.
-- start_state/feed_value reconstructed from integer stat snapshots (approx;
-- used only for AutoMagFeeder resume math).
return {
    target_mag = "Kama",
    sequence = {
        {
            step = 1,
            class_name = "FOmar",
            class_id = 10,
            section_id = "Redria",
            item_id = "0x030100",
            item = "Monofluid",
            count = 15,
            start_state = { level = 5, def = 5.00, pow = 0.00, dex = 0.00, mind = 0.00 },
            feed_value = { def = 0, pow = 0, dex = 0, mind = 33 }
        },
        {
            step = 2,
            class_name = "FOmar",
            class_id = 10,
            section_id = "Redria",
            item_id = "0x031300",
            item = "Antiparalysis",
            count = 132,
            start_state = { level = 10, def = 5.00, pow = 0.00, dex = 0.00, mind = 5.00 },
            feed_value = { def = 0, pow = 0, dex = 14, mind = 5 }
        },
        {
            step = 3,
            class_name = "FOmar",
            class_id = 10,
            section_id = "Redria",
            item_id = "0x030100",
            item = "Monofluid",
            count = 156,
            start_state = { level = 35, def = 5.00, pow = 0.00, dex = 19.00, mind = 11.00 },
            feed_value = { def = 0, pow = 0, dex = 0, mind = 10 }
        },
        {
            step = 4,
            class_name = "RAmar",
            class_id = 3,
            section_id = "Redria",
            item_id = "0x030900",
            item = "Antidote",
            count = 194,
            start_state = { level = 50, def = 5.00, pow = 0.00, dex = 19.00, mind = 26.00 },
            feed_value = { def = 0, pow = 0, dex = 16, mind = 0 }
        },
        {
            step = 5,
            class_name = "RAmar",
            class_id = 3,
            section_id = "Redria",
            item_id = "0x030100",
            item = "Monofluid",
            count = 189,
            start_state = { level = 81, def = 5.00, pow = 0.00, dex = 50.00, mind = 26.00 },
            feed_value = { def = 0, pow = 0, dex = 0, mind = 10 }
        }
    }
}
