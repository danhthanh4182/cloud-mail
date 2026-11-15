const encoder = new TextEncoder();

const saltHashUtils = {

	generateSalt(length = 16) {
		const array = new Uint8Array(length);
		crypto.getRandomValues(array);
		return btoa(String.fromCharCode(...array));
	},


	async hashPassword(password) {
		const salt = this.generateSalt();
		const hash = await this.genHashPassword(password, salt);
		return { salt, hash };
	},

	async genHashPassword(password, salt) {
		const data = encoder.encode(salt + password);
		const hashBuffer = await crypto.subtle.digest('SHA-256', data);
		const hashArray = Array.from(new Uint8Array(hashBuffer));
		return btoa(String.fromCharCode(...hashArray));
	},

	async verifyPassword(inputPassword, salt, storedHash) {
		const hash = await this.genHashPassword(inputPassword, salt);
		return hash === storedHash;
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

	genRandomPwd(length = 8) {
		const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
		let result = '';
		for (let i = 0; i < length; i++) {
			result += chars.charAt(Math.floor(Math.random() * chars.length));
		}
		return result;
	}
};

export default saltHashUtils;
