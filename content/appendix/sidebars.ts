import type { SidebarsConfig } from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  appendixSidebar: [
    'index',
    'kubectl',
    'ingress-error-code',
    'eks-note',
    {
      type: 'category',
      label: '策略管理',
      collapsed: false,
      link: {
        type: 'generated-index',
        slug: '/opa'
      },
      items: [
        'opa/install',
        'opa/block-public-ingress',
      ]
    }
  ]
};

export default sidebars;
