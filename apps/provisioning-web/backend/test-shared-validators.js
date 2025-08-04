#!/usr/bin/env node

/**
 * Test script for shared validators
 * Verifies that validation logic is consistent between frontend and backend
 */

const validators = require('../shared/validators');
const colors = require('colors/safe');

console.log('Testing Shared Validators\n');

let testsPassed = 0;
let testsFailed = 0;

function test(description, fn) {
  try {
    fn();
    console.log(colors.green('✓ ') + description);
    testsPassed++;
  } catch (error) {
    console.log(colors.red('✗ ') + description);
    console.log(colors.red('  ' + error.message));
    testsFailed++;
  }
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message || 'Assertion failed');
  }
}

// Test validateDomain
console.log('\n--- Domain Validation ---');

test('accepts localhost', () => {
  const result = validators.validateDomain('localhost');
  assert(result.valid === true, 'localhost should be valid');
});

test('accepts valid domain', () => {
  const result = validators.validateDomain('example.com');
  assert(result.valid === true, 'example.com should be valid');
});

test('accepts subdomain', () => {
  const result = validators.validateDomain('sub.example.com');
  assert(result.valid === true, 'sub.example.com should be valid');
});

test('accepts .local domains', () => {
  const result = validators.validateDomain('myserver.local');
  assert(result.valid === true, 'myserver.local should be valid');
});

test('rejects empty domain', () => {
  const result = validators.validateDomain('');
  assert(result.valid === false, 'empty domain should be invalid');
  assert(result.message === 'Domain is required', 'should have correct message');
});

test('rejects invalid domain format', () => {
  const result = validators.validateDomain('not_a_domain');
  assert(result.valid === false, 'not_a_domain should be invalid');
  assert(result.message.includes('Invalid domain format'), 'should have format error');
});

test('rejects domain with special characters', () => {
  const result = validators.validateDomain('example$.com');
  assert(result.valid === false, 'domain with $ should be invalid');
});

// Test validateEmail
console.log('\n--- Email Validation ---');

test('accepts valid email', () => {
  const result = validators.validateEmail('user@example.com');
  assert(result.valid === true, 'user@example.com should be valid');
});

test('accepts email with subdomain', () => {
  const result = validators.validateEmail('user@mail.example.com');
  assert(result.valid === true, 'user@mail.example.com should be valid');
});

test('rejects empty email', () => {
  const result = validators.validateEmail('');
  assert(result.valid === false, 'empty email should be invalid');
  assert(result.message === 'Email is required', 'should have correct message');
});

test('rejects email without @', () => {
  const result = validators.validateEmail('userexample.com');
  assert(result.valid === false, 'email without @ should be invalid');
});

test('rejects email without domain', () => {
  const result = validators.validateEmail('user@');
  assert(result.valid === false, 'email without domain should be invalid');
});

// Test validatePassword
console.log('\n--- Password Validation ---');

test('accepts empty password when allowed', () => {
  const result = validators.validatePassword('', true);
  assert(result.valid === true, 'empty password should be valid when allowed');
  assert(result.message === 'Password will be auto-generated', 'should indicate auto-generation');
});

test('rejects empty password when not allowed', () => {
  const result = validators.validatePassword('', false);
  assert(result.valid === false, 'empty password should be invalid when not allowed');
  assert(result.message === 'Password is required', 'should have correct message');
});

test('accepts strong password', () => {
  const result = validators.validatePassword('SecurePass123!');
  assert(result.valid === true, 'SecurePass123! should be valid');
  assert(result.strength === 'strong', 'should be marked as strong');
});

test('rejects short password', () => {
  const result = validators.validatePassword('Pass1');
  assert(result.valid === false, 'short password should be invalid');
  assert(result.message.includes('at least 8 characters'), 'should mention length requirement');
});

test('rejects password without uppercase', () => {
  const result = validators.validatePassword('password123');
  assert(result.valid === false, 'password without uppercase should be invalid');
  assert(result.message.includes('one uppercase letter'), 'should mention uppercase requirement');
});

test('rejects password without lowercase', () => {
  const result = validators.validatePassword('PASSWORD123');
  assert(result.valid === false, 'password without lowercase should be invalid');
  assert(result.message.includes('one lowercase letter'), 'should mention lowercase requirement');
});

test('rejects password without number', () => {
  const result = validators.validatePassword('PasswordOnly');
  assert(result.valid === false, 'password without number should be invalid');
  assert(result.message.includes('one number'), 'should mention number requirement');
});

// Test validateAdminName
console.log('\n--- Admin Name Validation ---');

test('accepts valid name', () => {
  const result = validators.validateAdminName('John Doe');
  assert(result.valid === true, 'John Doe should be valid');
});

test('accepts name with hyphen', () => {
  const result = validators.validateAdminName('Mary-Jane');
  assert(result.valid === true, 'Mary-Jane should be valid');
});

test('accepts name with apostrophe', () => {
  const result = validators.validateAdminName("O'Brien");
  assert(result.valid === true, "O'Brien should be valid");
});

test('rejects empty name', () => {
  const result = validators.validateAdminName('');
  assert(result.valid === false, 'empty name should be invalid');
});

test('rejects name with numbers', () => {
  const result = validators.validateAdminName('John123');
  assert(result.valid === false, 'name with numbers should be invalid');
});

// Test validateServiceUrl
console.log('\n--- Service URL Validation ---');

test('accepts localhost with port', () => {
  const result = validators.validateServiceUrl('localhost:3000');
  assert(result.valid === true, 'localhost:3000 should be valid');
});

test('accepts subdomain format', () => {
  const result = validators.validateServiceUrl('app.example.com');
  assert(result.valid === true, 'app.example.com should be valid');
});

test('rejects invalid service URL', () => {
  const result = validators.validateServiceUrl('not-a-url');
  assert(result.valid === false, 'single word should be invalid');
  assert(result.message.includes('service.domain.com'), 'should mention correct format');
});

// Summary
console.log('\n' + '='.repeat(50));
console.log(colors.bold('Test Summary:'));
console.log(colors.green(`✓ Passed: ${testsPassed}`));
if (testsFailed > 0) {
  console.log(colors.red(`✗ Failed: ${testsFailed}`));
  process.exit(1);
} else {
  console.log(colors.green('\nAll tests passed! 🎉'));
}