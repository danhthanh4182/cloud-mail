const encoder = new TextEncoder();

// Keep 100000 for compatibility: it is workerd's default maximum
// (DEFAULT_MAX_PBKDF2_ITERATIONS = 100'000); larger values raise NotSupportedError.
const PBKDF2_ITERATIONS = 100000;
const PBKDF2_PREFIX = 'pbkdf2-sha256';
const RANDOM_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
const REJECTION_LIMIT = 256 - (256 % RANDOM_CHARS.length);

async function pbkdf2Bytes(password, saltBytes, iterations, bitLength) {
	const key = await crypto.subtle.importKey(
		'raw',
		encoder.encode(password),
		{ name: 'PBKDF2' },
		false,
		['deriveBits']
	);
	const bits = await crypto.subtle.deriveBits(
		{ name: 'PBKDF2', salt: saltBytes, iterations, hash: 'SHA-256' },
		key,
		bitLength
	);
	return new Uint8Array(bits);
}

const saltHashUtils = {

	generateSalt(length = 16) {
		const array = new Uint8Array(length);
		crypto.getRandomValues(array);
		return btoa(String.fromCharCode(...array));
	},

	async hashPassword(password) {
		const salt = this.generateSalt();
		const derived = await pbkdf2Bytes(password, encoder.encode(salt), PBKDF2_ITERATIONS, 256);
		return { salt, hash: `${PBKDF2_PREFIX}$${PBKDF2_ITERATIONS}$${btoa(String.fromCharCode(...derived))}` };
	},

	async legacyHashPassword(password, salt) {
		const data = encoder.encode(salt + password);
		const hashBuffer = await crypto.subtle.digest('SHA-256', data);
		const hashArray = Array.from(new Uint8Array(hashBuffer));
		return btoa(String.fromCharCode(...hashArray));
	},

	async verifyPasswordWithStatus(inputPassword, salt, storedHash) {
		if (!storedHash || !storedHash.startsWith(`${PBKDF2_PREFIX}$`)) {
			const legacy = await this.legacyHashPassword(inputPassword, salt);
			const valid = this.timingSafeEqualString(legacy, String(storedHash ?? ''));
			return { valid, needsRehash: valid };
		}
		const parts = storedHash.split('$');
		if (parts.length !== 3) {
			return { valid: false, needsRehash: false };
		}
		const iterations = Number.parseInt(parts[1], 10);
		if (!Number.isFinite(iterations) || iterations <= 0) {
			return { valid: false, needsRehash: false };
		}
		let expected;
		try {
			expected = Uint8Array.from(atob(parts[2]), (ch) => ch.charCodeAt(0));
		} catch {
			return { valid: false, needsRehash: false };
		}
		const derived = await pbkdf2Bytes(inputPassword, encoder.encode(salt), iterations, expected.length * 8);
		const valid = this.timingSafeEqualBytes(derived, expected);
		return { valid, needsRehash: false };
	},

	async verifyPassword(inputPassword, salt, storedHash) {
		return (await this.verifyPasswordWithStatus(inputPassword, salt, storedHash)).valid;
	},

	timingSafeEqualBytes(a, b) {
		const left = a instanceof Uint8Array ? a : new Uint8Array(a || []);
		const right = b instanceof Uint8Array ? b : new Uint8Array(b || []);
		if (typeof crypto?.subtle?.timingSafeEqual === 'function') {
			try {
				return crypto.subtle.timingSafeEqual(left, right);
			} catch {
				return false;
			}
		}
		if (left.length !== right.length) {
			return false;
		}
		let diff = 0;
		for (let i = 0; i < left.length; i++) {
			diff |= left[i] ^ right[i];
		}
		return diff === 0;
	},

	timingSafeEqualString(a, b) {
		return this.timingSafeEqualBytes(encoder.encode(String(a ?? '')), encoder.encode(String(b ?? '')));
	},

	genRandomPwd(length = 16) {
		let result = '';
		while (result.length < length) {
			const random = new Uint8Array(length - result.length);
			crypto.getRandomValues(random);
			for (const byte of random) {
				if (byte < REJECTION_LIMIT) {
					result += RANDOM_CHARS[byte % RANDOM_CHARS.length];
					if (result.length === length) {
						break;
					}
				}
			}
		}
		return result;
	}
};

export default saltHashUtils;
