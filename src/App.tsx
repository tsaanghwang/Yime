import React from 'react';
import InputMethodEngine from './core/InputMethodEngine';
import { ThemeProvider } from './components/ThemeProvider';

function App() {
  return (
    <ThemeProvider>
      <div className="min-h-screen bg-base-100">
        <InputMethodEngine />
      </div>
    </ThemeProvider>
  );
}

export default App;