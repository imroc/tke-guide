import type { SidebarsConfig } from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  yamlSidebar: [
    'index',
    'public-service-or-ingress-connect-failed',
    {
      type: 'category',
      label: '常见问题',
      collapsed: false,
      link: {
        type: 'generated-index',
        slug: '/faq'
      },
      items: [
        'faq/modify-rp-filter-causing-exception',
        'faq/clb-loopback',
        'faq/controller-manager-and-scheduler-unhealthy',
      ]
    }
  ]
};

export default sidebars;
