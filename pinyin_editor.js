// 音元拼音标调规则编辑器逻辑
document.addEventListener('DOMContentLoaded', function() {
    // 获取DOM元素
    const applyBtn = document.querySelector('.btn-primary');
    const ieCheckbox = document.querySelector('input[type="checkbox"]');
    const nasalToneSelect = document.querySelectorAll('select')[0];
    const triphthongToneSelect = document.querySelectorAll('select')[1];
    const resultAlert = document.querySelector('.alert');

    // 应用修改按钮点击事件
    applyBtn.addEventListener('click', function() {
        // 获取用户选择的选项
        const fixIe = ieCheckbox.checked;
        const nasalTonePos = nasalToneSelect.value;
        const triphthongTonePos = triphthongToneSelect.value;

        // 验证用户是否选择了所有选项
        if (nasalToneSelect.selectedIndex === 0 || triphthongToneSelect.selectedIndex === 0) {
            showAlert('请选择所有标调位置选项', 'error');
            return;
        }

        // 构建修改规则对象
        const modificationRules = {
            fixIeToE: fixIe,
            nasalTonePosition: nasalTonePos,
            triphthongTonePosition: triphthongTonePos,
            timestamp: new Date().toISOString()
        };

        // 显示成功消息
        showAlert('规则修改已应用! 请查看下方预览', 'success');
        
        // 这里可以添加AJAX请求将修改发送到服务器
        console.log('应用的修改规则:', modificationRules);
    });

    // 显示提示消息
    function showAlert(message, type) {
        resultAlert.querySelector('span').textContent = message;
        resultAlert.className = `alert alert-${type} shadow-lg`;
        resultAlert.style.display = 'flex';
    }

    // 初始化编辑器状态
    function initEditor() {
        // 默认选中第一个选项
        nasalToneSelect.selectedIndex = 1;
        triphthongToneSelect.selectedIndex = 1;
    }

    initEditor();
});