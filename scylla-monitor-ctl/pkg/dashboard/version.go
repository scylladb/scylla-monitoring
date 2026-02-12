package dashboard

import (
	"regexp"
	"strconv"
	"strings"
)

const MasterVersion = 666

// ParseVersion converts a version string like "5.4" or "master" into an int slice.
func ParseVersion(v string) []int {
	if v == "master" {
		return []int{MasterVersion}
	}
	parts := strings.Split(v, ".")
	result := make([]int, 0, len(parts))
	for _, p := range parts {
		n, err := strconv.Atoi(p)
		if err != nil {
			continue
		}
		result = append(result, n)
	}
	return result
}

var cmpVersionRe = regexp.MustCompile(`^([^\d]+)\s*([\d\.]+)\s*$`)

// IsVersionBigger checks if 'version' satisfies the cmpVersion constraint.
// cmpVersion can be "5.4" (exact match), ">5.0" (greater than), "<2024.1" (less than).
// Faithfully ports the Python is_version_bigger function.
func IsVersionBigger(version []int, cmpVersion string) bool {
	cmpOp := 0 // 0 = exact/>=, 1 = >, -1 = <

	m := cmpVersionRe.FindStringSubmatch(cmpVersion)
	if m != nil {
		cmpVersion = m[2]
		switch strings.TrimSpace(m[1]) {
		case ">":
			cmpOp = 1
		case "<":
			cmpOp = -1
		}
	}

	if len(version) > 0 && version[0] == MasterVersion {
		return cmpOp == 1
	}

	cmpParts := strings.Split(cmpVersion, ".")
	if len(cmpParts) == 0 {
		return false
	}

	cmpFirst, err := strconv.Atoi(cmpParts[0])
	if err != nil {
		return false
	}

	// Check if version and cmpVersion are the same "type" (enterprise vs OSS)
	if len(version) > 0 && (version[0] > 1900) != (cmpFirst > 1900) {
		return false
	}

	ln := len(cmpParts)
	if len(version) < ln {
		ln = len(version)
	}

	for i := 0; i < ln; i++ {
		cmpVal, err := strconv.Atoi(cmpParts[i])
		if err != nil {
			return false
		}
		if (cmpOp == 0 && version[i] != cmpVal) ||
			(cmpOp > 0 && version[i] < cmpVal) ||
			(cmpOp < 0 && version[i] > cmpVal) {
			return false
		}
		if (cmpOp > 0 && version[i] > cmpVal) ||
			(cmpOp < 0 && version[i] < cmpVal) {
			return true
		}
	}

	// If we got here, version == cmpVersion for the compared parts
	return cmpOp >= 0
}

// ShouldVersionReject returns true if the object should be rejected based on version.
func ShouldVersionReject(version []int, obj map[string]interface{}) bool {
	if len(version) == 0 {
		return false
	}
	dv, ok := obj["dashversion"]
	if !ok {
		return false
	}

	// dashversion can be a string or a list of strings
	switch v := dv.(type) {
	case string:
		return !IsVersionBigger(version, v)
	case []interface{}:
		for _, item := range v {
			s, ok := item.(string)
			if !ok {
				continue
			}
			if IsVersionBigger(version, s) {
				return false
			}
		}
		return true
	}
	return false
}
