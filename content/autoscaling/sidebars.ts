import type { SidebarsConfig } from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  autoscalingSidebar: [
    'index',
    {
      type: 'category',
      label: '基于 KEDA 的高级弹性伸缩最佳实践',
      collapsed: false,
      link: {
        type: 'generated-index',
        slug: '/keda'
      },
      items: [
        'keda/overview',
        'keda/install',
        'keda/cron',
      ]
    },
  ]
};

export default sidebars;
