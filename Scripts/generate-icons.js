const { createCanvas } = require('canvas');
const fs = require('fs');
const path = require('path');

function generateIcon(size, outputPath) {
  const canvas = createCanvas(size, size);
  const ctx = canvas.getContext('2d');

  // Background gradient - deep space
  const grad = ctx.createLinearGradient(0, 0, size, size);
  grad.addColorStop(0, '#1a1a2e');
  grad.addColorStop(1, '#0f0f1a');
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, size, size);

  // Outer glow ring
  const ringRadius = size * 0.38;
  const ringGrad = ctx.createRadialGradient(size/2, size/2, ringRadius*0.7, size/2, size/2, ringRadius);
  ringGrad.addColorStop(0, 'rgba(107, 71, 230, 0.15)');
  ringGrad.addColorStop(1, 'rgba(71, 43, 184, 0)');
  ctx.fillStyle = ringGrad;
  ctx.beginPath();
  ctx.arc(size/2, size/2 + size*0.02, ringRadius, 0, Math.PI * 2);
  ctx.fill();

  // Camera viewfinder icon (two crossing lines + circle)
  const cx = size / 2;
  const cy = size / 2 + size * 0.03;
  const radius = size * 0.18;
  const lineWidth = Math.max(2, size * 0.012);

  ctx.strokeStyle = '#6B47E6';
  ctx.lineWidth = lineWidth;
  ctx.lineCap = 'round';

  // Outer circle
  ctx.beginPath();
  ctx.arc(cx, cy, radius + lineWidth, 0, Math.PI * 2);
  ctx.stroke();

  // Inner circle
  ctx.beginPath();
  ctx.arc(cx, cy, radius * 0.4, 0, Math.PI * 2);
  ctx.stroke();

  // Crosshairs
  ctx.beginPath();
  ctx.moveTo(cx - radius - lineWidth, cy);
  ctx.lineTo(cx + radius + lineWidth, cy);
  ctx.moveTo(cx, cy - radius - lineWidth);
  ctx.lineTo(cx, cy + radius + lineWidth);
  ctx.stroke();

  // Small corner brackets (camera style)
  ctx.lineWidth = lineWidth * 0.7;
  const bl = size * 0.12;
  // Top-left bracket
  ctx.beginPath();
  ctx.moveTo(size * 0.18, size * 0.18);
  ctx.lineTo(size * 0.18 + bl, size * 0.18);
  ctx.lineTo(size * 0.18, size * 0.18 + bl);
  ctx.stroke();
  // Top-right bracket
  ctx.beginPath();
  ctx.moveTo(size * 0.82, size * 0.18);
  ctx.lineTo(size * 0.82 - bl, size * 0.18);
  ctx.lineTo(size * 0.82, size * 0.18 + bl);
  ctx.stroke();
  // Bottom-left bracket
  ctx.beginPath();
  ctx.moveTo(size * 0.18, size * 0.82);
  ctx.lineTo(size * 0.18 + bl, size * 0.82);
  ctx.lineTo(size * 0.18, size * 0.82 - bl);
  ctx.stroke();
  // Bottom-right bracket
  ctx.beginPath();
  ctx.moveTo(size * 0.82, size * 0.82);
  ctx.lineTo(size * 0.82 - bl, size * 0.82);
  ctx.lineTo(size * 0.82, size * 0.82 - bl);
  ctx.stroke();

  // "Whamrando" text below
  ctx.font = 'bold ' + (size * 0.11) + 'px -apple-system, BlinkMacSystemFont, sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillStyle = 'rgba(255, 255, 255, 0.9)';
  ctx.fillText('Whamrando', cx, size * 0.83);

  // Subtle highlight
  ctx.shadowColor = 'rgba(107, 71, 230, 0.4)';
  ctx.shadowBlur = size * 0.05;
  ctx.beginPath();
  ctx.arc(cx, cy, radius * 0.5, 0, Math.PI * 2);
  ctx.fillStyle = 'rgba(107, 71, 230, 0.1)';
  ctx.fill();
  ctx.shadowBlur = 0;

  const buf = canvas.toBuffer('image/png');
  fs.writeFileSync(outputPath, buf);
  console.log('Created: ' + outputPath);
}

const iconDir = path.join(__dirname, '..', 'App', 'Assets.xcassets', 'AppIcon.appiconset');

const sizes = [
  { size: 20, suffix: '' },
  { size: 29, suffix: '' },
  { size: 40, suffix: '' },
  { size: 58, suffix: '@2x' },
  { size: 60, suffix: '@2x' },
  { size: 76, suffix: '' },
  { size: 80, suffix: '@2x' },
  { size: 87, suffix: '@2x' },
  { size: 120, suffix: '@2x' },
  { size: 152, suffix: '@2x' },
  { size: 167, suffix: '@2x' },
  { size: 1024, suffix: '' },
  { size: 20, suffix: '@3x' },
  { size: 29, suffix: '@3x' },
  { size: 40, suffix: '@3x' },
  { size: 60, suffix: '@3x' },
];

for (const item of sizes) {
  const { size, suffix } = item;
  const filename = suffix ? 'AppIcon-' + size + suffix + '.png' : 'AppIcon-' + size + '.png';
  generateIcon(size, path.join(iconDir, filename));
}

console.log('All ' + sizes.length + ' icons generated successfully!');
