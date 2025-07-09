import React, { useState, useEffect } from 'react';
import { getMatchedWordsByPinyin } from '../services/pinyinService';

const InputMethodEngine: React.FC = () => {
  const [input, setInput] = useState('');
  const [candidates, setCandidates] = useState<string[]>([]);
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [isChecking, setIsChecking] = useState(false);
  const [needsUpdate, setNeedsUpdate] = useState(false);

  useEffect(() => {
    if (input.length > 0) {
      setIsChecking(true);
      setTimeout(() => {
        const matches = getMatchedWordsByPinyin(input);
        setCandidates(matches);
        setSelectedIndex(0);
        setIsChecking(false);
        
        // 模拟检查是否需要更新
        if (Math.random() > 0.7) {
          setNeedsUpdate(true);
        }
      }, 500);
    } else {
      setCandidates([]);
      setNeedsUpdate(false);
    }
  }, [input]);

  const handleSelect = (index: number) => {
    if (index >= 0 && index < candidates.length) {
      console.log(`Selected: ${candidates[index]}`);
      setInput('');
    }
  };

  return (
    <div className="p-4 max-w-md mx-auto">
      <div className="join join-vertical w-full">
        <input
          type="text"
          className="input input-bordered join-item w-full"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="输入拼音..."
        />
        {isChecking && (
          <div className="join-item bg-base-200 rounded-b-lg p-4 flex justify-center">
            <span className="loading loading-spinner loading-md"></span>
            <span className="ml-2">检查中...</span>
          </div>
        )}
        {needsUpdate && (
          <div className="join-item bg-warning/10 rounded-b-lg p-4">
            <div className="alert alert-warning shadow-lg">
              <div>
                <svg xmlns="http://www.w3.org/2000/svg" className="stroke-current flex-shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
                <span>检测到需要更新的内容，等待前端确认...</span>
              </div>
            </div>
          </div>
        )}
        {!isChecking && candidates.length > 0 && (
          <div className="join-item bg-base-200 rounded-b-lg p-2">
            {candidates.map((word, index) => (
              <button
                key={index}
                className={`btn btn-sm m-1 ${selectedIndex === index ? 'btn-primary' : 'btn-ghost'}`}
                onClick={() => handleSelect(index)}
              >
                {word}
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

export default InputMethodEngine;