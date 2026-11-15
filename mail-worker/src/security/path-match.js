export function matchesPathPrefix(path, prefix) {
	return path === prefix || path.startsWith(prefix + '/');
}
