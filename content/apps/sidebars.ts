import type { SidebarsConfig } from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  appsSidebar: [
    'index',
    'upgrade-inplace',
    {
      type: 'category',
      label: '常见应用部署',
      collapsed: false,
      link: {
        type: 'generated-index',
        slug: '/deploy'
      },
      items: [
        'deploy/harbor',
        'deploy/gitlab',
        'deploy/kubesphere',
      ]
    }
  ]
};

export default sidebars;
