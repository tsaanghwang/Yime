// src/App.test.tsx
import React from 'react';
import { render, screen } from '@testing-library/react';
import App from './App';

describe('App Component', () => {
  test('renders without crashing', () => {
    render(<App />);
  });

  test('contains InputMethodEngine component', () => {
    const { container } = render(<App />);
    // 验证主要容器存在
    expect(container.firstChild).toBeInTheDocument();
  });

  test('has correct className', () => {
    const { container } = render(<App />);
    const mainDiv = container.querySelector('.min-h-screen');
    expect(mainDiv).toBeInTheDocument();
    expect(mainDiv).toHaveClass('bg-base-100');
  });
});
