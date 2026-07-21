export const MINIMUM_PASSWORD_LENGTH = 12;

export function validatePassword(password: string) {
  if (password.length < MINIMUM_PASSWORD_LENGTH) {
    return false;
  }

  return (
    /[a-z]/.test(password) &&
    /[A-Z]/.test(password) &&
    /\d/.test(password) &&
    /[^A-Za-z0-9\s]/.test(password)
  );
}