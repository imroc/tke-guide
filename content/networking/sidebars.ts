import type { SidebarsConfig } from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  networkingSidebar: [
    'index',
    {
      type: 'category',
      label: '在 TKE 自建 Nginx Ingress Controller',
      collapsed: true,
      link: {
        type: 'generated-index',
        slug: '/ingress-nginx'
      },
      items: [
        'ingress-nginx/quick-start',
        'ingress-nginx/clb',
        'ingress-nginx/clb-direct-access',
        'ingress-nginx/high-concurrency',
        'ingress-nginx/high-availability',
        'ingress-nginx/observability',
        'ingress-nginx/waf',
        'ingress-nginx/multi-ingress-controller',
        'ingress-nginx/migrate',
        'ingress-nginx/values-demo',
      ],
    },
    'traffic-lossless-upgrade',
    'clb-to-pod-directly',
    'how-to-use-eip',
    'install-localdns-with-ipvs',
    'expose-grpc-with-tcm',
  ]
};

export default sidebars;
