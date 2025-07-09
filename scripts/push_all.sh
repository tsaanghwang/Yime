#!/bin/bash
# scripts/push_all.sh
echo "正在推送代码到 origin 仓库..."
git push origin main || echo "origin 推送失败"

echo "正在推送代码到 gitcode 仓库..."
git push gitcode main || echo "gitcode 推送失败"