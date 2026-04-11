// src/components/ThemeProvider.test.tsx
import React from 'react';
import { render, screen, act } from '@testing-library/react';
import { ThemeProvider, useTheme } from './ThemeProvider';

// 测试组件，用于访问 theme context
const TestComponent = () => {
  const { theme, setTheme } = useTheme();
  return (
    <div>
      <span data-testid="theme-value">{theme}</span>
      <button onClick={() => setTheme('dark')}>Set Dark</button>
      <button onClick={() => setTheme('cupcake')}>Set Cupcake</button>
    </div>
  );
};

describe('ThemeProvider', () => {
  beforeEach(() => {
    // 清除 localStorage
    localStorage.clear();
  });

  test('provides default theme', () => {
    render(
      <ThemeProvider>
        <TestComponent />
      </ThemeProvider>
    );

    const themeValue = screen.getByTestId('theme-value');
    expect(themeValue).toHaveTextContent('light');
  });

  test('allows theme change', () => {
    render(
      <ThemeProvider>
        <TestComponent />
      </ThemeProvider>
    );

    const themeValue = screen.getByTestId('theme-value');
    const darkButton = screen.getByText('Set Dark');

    act(() => {
      darkButton.click();
    });

    expect(themeValue).toHaveTextContent('dark');
  });

  test('saves theme to localStorage', () => {
    render(
      <ThemeProvider>
        <TestComponent />
      </ThemeProvider>
    );

    const darkButton = screen.getByText('Set Dark');

    act(() => {
      darkButton.click();
    });

    expect(localStorage.getItem('inputMethodTheme')).toBe('dark');
  });

  test('loads theme from localStorage', () => {
    localStorage.setItem('inputMethodTheme', 'synthwave');

    render(
      <ThemeProvider>
        <TestComponent />
      </ThemeProvider>
    );

    const themeValue = screen.getByTestId('theme-value');
    expect(themeValue).toHaveTextContent('synthwave');
  });

  test('throws error when useTheme is used outside ThemeProvider', () => {
    // 抑制 console.error
    const consoleError = console.error;
    console.error = jest.fn();

    expect(() => {
      render(<TestComponent />);
    }).toThrow('useTheme must be used within a ThemeProvider');

    // 恢复 console.error
    console.error = consoleError;
  });
});
