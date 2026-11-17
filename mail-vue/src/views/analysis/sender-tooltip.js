export function formatSenderTooltip(params) {
  const tooltip = document.createElement('span');
  const marker = document.createElement('span');
  marker.style.cssText = 'display:inline-block;margin-right:4px;border-radius:10px;width:10px;height:10px;';
  if (typeof params.color === 'string') marker.style.backgroundColor = params.color;
  tooltip.append(marker, document.createTextNode(` ${params.name}： ${params.value} (${params.percent}%)`));
  return tooltip;
}
