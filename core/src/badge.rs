//! Dock badge text and its menu-bar-sized form.

use serde::Serialize;

/// Longest text badge shown verbatim in the menu bar.
const MAX_TEXT_CHARS: usize = 4;

/// The badge an app shows on its Dock icon.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Badge {
    /// The badge text exactly as the app set it, trimmed.
    pub label: String,
    /// A compact form that fits in the menu bar, e.g. `1.2K`.
    pub short: String,
    /// The numeric value, when the badge is a plain count.
    pub count: Option<u64>,
}

impl Badge {
    /// Parses raw badge text. Blank text means "no badge".
    pub fn parse(raw: &str) -> Option<Badge> {
        let label = raw.trim();
        if label.is_empty() {
            return None;
        }
        let count = parse_count(label);
        let short = match count {
            Some(count) => compact(count),
            None => truncate(label),
        };
        Some(Badge {
            label: label.to_string(),
            short,
            count,
        })
    }
}

/// Reads `label` as a count, accepting grouped digits such as `1,234`,
/// `1.234` or `1 234`. Anything else (`99+`, `1.5`, `•`) is not a count.
fn parse_count(label: &str) -> Option<u64> {
    let is_separator = |c: char| matches!(c, ',' | '.' | '\'' | ' ' | '\u{a0}' | '\u{202f}');
    let mut groups = label.split(is_separator);

    let first = groups.next()?;
    if first.is_empty() || !first.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let mut digits = first.to_string();
    for group in groups {
        if group.len() != 3 || !group.bytes().all(|b| b.is_ascii_digit()) {
            return None;
        }
        digits.push_str(group);
    }
    digits.parse().ok()
}

/// Shortens a count to at most four characters, rounding down: `1234` → `1.2K`.
fn compact(count: u64) -> String {
    const UNITS: [(u64, &str); 3] = [(1_000_000_000, "B"), (1_000_000, "M"), (1_000, "K")];

    for (size, suffix) in UNITS {
        if count < size {
            continue;
        }
        let whole = count / size;
        let tenth = count % size / (size / 10);
        return match (whole, tenth) {
            (1..=9, 1..) => format!("{whole}.{tenth}{suffix}"),
            (..=999, _) => format!("{whole}{suffix}"),
            _ => format!("999{suffix}+"),
        };
    }
    count.to_string()
}

fn truncate(label: &str) -> String {
    if label.chars().count() <= MAX_TEXT_CHARS {
        return label.to_string();
    }
    let head: String = label.chars().take(MAX_TEXT_CHARS - 1).collect();
    format!("{head}…")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn short(raw: &str) -> String {
        Badge::parse(raw).expect("badge").short
    }

    #[test]
    fn blank_text_is_no_badge() {
        assert_eq!(Badge::parse(""), None);
        assert_eq!(Badge::parse("  \n"), None);
    }

    #[test]
    fn plain_counts() {
        let badge = Badge::parse(" 3 ").unwrap();
        assert_eq!(badge.label, "3");
        assert_eq!(badge.short, "3");
        assert_eq!(badge.count, Some(3));
        assert_eq!(Badge::parse("0").unwrap().count, Some(0));
        assert_eq!(Badge::parse("999").unwrap().short, "999");
    }

    #[test]
    fn grouped_counts() {
        assert_eq!(Badge::parse("1,234").unwrap().count, Some(1234));
        assert_eq!(Badge::parse("1.234").unwrap().count, Some(1234));
        assert_eq!(Badge::parse("12\u{a0}345\u{a0}678").unwrap().count, Some(12_345_678));
    }

    #[test]
    fn text_that_is_not_a_count() {
        for raw in ["99+", "1.5", "1,23", ",123", "•", "!", "1.2K", "１２"] {
            assert_eq!(Badge::parse(raw).unwrap().count, None, "{raw}");
        }
        assert_eq!(short("99+"), "99+");
        assert_eq!(short("•"), "•");
    }

    #[test]
    fn large_counts_are_compacted() {
        assert_eq!(short("1000"), "1K");
        assert_eq!(short("1234"), "1.2K");
        assert_eq!(short("9999"), "9.9K");
        assert_eq!(short("12345"), "12K");
        assert_eq!(short("999999"), "999K");
        assert_eq!(short("1500000"), "1.5M");
        assert_eq!(short("18446744073709551615"), "999B+");
    }

    #[test]
    fn counts_too_large_for_u64_stay_text() {
        let badge = Badge::parse("99999999999999999999").unwrap();
        assert_eq!(badge.count, None);
        assert_eq!(badge.short, "999…");
    }

    #[test]
    fn long_text_is_truncated() {
        assert_eq!(short("NEW"), "NEW");
        assert_eq!(short("LIVE"), "LIVE");
        assert_eq!(short("UPDATE"), "UPD…");
    }
}
