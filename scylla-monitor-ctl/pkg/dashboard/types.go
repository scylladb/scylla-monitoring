package dashboard

// ResolveType resolves a type name against the types map, following class-based inheritance.
// Parent fields are added to the result only if the child doesn't already have them.
func ResolveType(name string, types map[string]interface{}) map[string]interface{} {
	return resolveTypeWithVisited(name, types, map[string]bool{})
}

func resolveTypeWithVisited(name string, types map[string]interface{}, visited map[string]bool) map[string]interface{} {
	if visited[name] {
		return map[string]interface{}{}
	}
	t, ok := types[name]
	if !ok {
		return map[string]interface{}{}
	}
	tMap, ok := t.(map[string]interface{})
	if !ok {
		return map[string]interface{}{}
	}
	className, hasClass := tMap["class"].(string)
	if !hasClass {
		return copyMap(tMap)
	}
	visited[name] = true
	result := copyMap(tMap)
	parent := resolveTypeWithVisited(className, types, visited)
	for k, v := range parent {
		if _, exists := result[k]; !exists {
			result[k] = v
		}
	}
	return result
}

// ShouldProductReject returns true if the object should be rejected based on product filters.
func ShouldProductReject(products []string, obj map[string]interface{}) bool {
	if dp, ok := obj["dashproduct"]; ok {
		dpStr, _ := dp.(string)
		if dpStr == "" && len(products) > 0 {
			return true
		}
		if dpStr != "" {
			found := false
			for _, p := range products {
				if p == dpStr {
					found = true
					break
				}
			}
			if !found {
				return true
			}
		}
	}
	if dpr, ok := obj["dashproductreject"]; ok {
		dprStr, _ := dpr.(string)
		for _, p := range products {
			if p == dprStr {
				return true
			}
		}
	}
	return false
}

// UpdateObject recursively processes a JSON object tree:
// - Resolves "class" references from types
// - Replaces "id": "auto" with auto-incrementing integers
// - Filters by version (dashversion)
// - Filters by product (dashproduct/dashproductreject)
// - Applies exact-match replacements
// - Recurses into arrays and nested objects
func UpdateObject(obj interface{}, types map[string]interface{}, version []int, products []string, exactMatch map[string]interface{}, idCounter *int) interface{} {
	objMap, ok := obj.(map[string]interface{})
	if !ok {
		return obj
	}

	// Resolve class
	if className, ok := objMap["class"].(string); ok {
		extra := ResolveType(className, types)
		for key, val := range extra {
			if _, exists := objMap[key]; !exists {
				objMap[key] = val
			}
		}
	}

	// Version and product rejection
	if (len(version) > 0 && ShouldVersionReject(version, objMap)) || ShouldProductReject(products, objMap) {
		return nil
	}

	for k, v := range objMap {
		if k == "id" {
			if s, ok := v.(string); ok && s == "auto" {
				objMap[k] = *idCounter
				*idCounter++
				continue
			}
		}

		switch val := v.(type) {
		case []interface{}:
			newArr := make([]interface{}, 0, len(val))
			for _, item := range val {
				result := UpdateObject(item, types, version, products, exactMatch, idCounter)
				if result != nil {
					newArr = append(newArr, result)
				}
			}
			objMap[k] = newArr
		case map[string]interface{}:
			result := UpdateObject(val, types, version, products, exactMatch, idCounter)
			if result != nil {
				objMap[k] = result
			}
		default:
			if s, ok := v.(string); ok {
				if replacement, found := exactMatch[s]; found {
					objMap[k] = replacement
				}
			}
		}
	}

	return objMap
}

// copyMap creates a shallow copy of a map.
func copyMap(m map[string]interface{}) map[string]interface{} {
	result := make(map[string]interface{}, len(m))
	for k, v := range m {
		result[k] = v
	}
	return result
}
