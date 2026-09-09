package main

import (
    "fmt"
    "math"
    "strconv"
    "strings"
    "time"
)

// These helpers preserve crictl's --since parsing without embedding the full
// Docker daemon module, which is unrelated to crictl and carries daemon CVEs.
func getTimestamp(value string, reference time.Time) (string, error) {
    if d, err := time.ParseDuration(value); value != "0" && err == nil {
        return strconv.FormatInt(reference.Add(-d).Unix(), 10), nil
    }

    parseInLocation := !strings.ContainsAny(value, "zZ+") && strings.Count(value, "-") != 3
    format := "2006-01-02"
    if strings.Contains(value, ".") {
        format = time.RFC3339Nano
        if parseInLocation {
            format = "2006-01-02T15:04:05.999999999"
        }
    } else if strings.Contains(value, "T") {
        colons := strings.Count(value, ":")
        if !parseInLocation && !strings.ContainsAny(value, "zZ") && colons > 0 {
            colons--
        }
        if colons > 2 {
            colons = 2
        }
        if parseInLocation {
            format = []string{"2006-01-02T15", "2006-01-02T15:04", "2006-01-02T15:04:05"}[colons]
        } else {
            format = []string{"2006-01-02T15Z07:00", "2006-01-02T15:04Z07:00", time.RFC3339}[colons]
        }
    } else if !parseInLocation {
        format = "2006-01-02Z07:00"
    }

    var parsed time.Time
    var err error
    if parseInLocation {
        _, offset := reference.Zone()
        parsed, err = time.ParseInLocation(format, value, time.FixedZone("", offset))
    } else {
        parsed, err = time.Parse(format, value)
    }
    if err == nil {
        return fmt.Sprintf("%d.%09d", parsed.Unix(), parsed.Nanosecond()), nil
    }
    if strings.Contains(value, "-") {
        return "", err
    }
    if _, _, unixErr := parseTimestamps(value, 0); unixErr != nil {
        return "", fmt.Errorf("failed to parse value as time or duration: %q", value)
    }
    return value, nil
}

func parseTimestamps(value string, defaultSeconds int64) (int64, int64, error) {
    if value == "" {
        return defaultSeconds, 0, nil
    }
    secondsPart, nanosPart, hasNanos := strings.Cut(value, ".")
    seconds, err := strconv.ParseInt(secondsPart, 10, 64)
    if err != nil || !hasNanos {
        return seconds, 0, err
    }
    nanos, err := strconv.ParseInt(nanosPart, 10, 64)
    if err != nil {
        return seconds, nanos, err
    }
    nanos = int64(float64(nanos) * math.Pow10(9-len(nanosPart)))
    return seconds, nanos, nil
}
