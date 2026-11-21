// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import groups from './src/data/groups.json' with { type: 'json' };

const site = 'https://wilsonnet.github.io';
const base = '/vinland-ui';

export default defineConfig({
	site,
	base,
	trailingSlash: 'always',
	integrations: [
		starlight({
			title: 'vinland-ui',
			description: 'A utility-first UI framework for Odin: Tailwind-style classes, design tokens, crisp GPU text, Vulkan with OpenGL fallback, and a CLI so agents can drive your app.',
			logo: { src: './src/assets/logo.svg', replacesTitle: false },
			favicon: '/favicon.svg',
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/WilsonNet/vinland-ui' }],
			editLink: { baseUrl: 'https://github.com/WilsonNet/vinland-ui/edit/main/website/' },
			customCss: ['./src/styles/custom.css'],
			lastUpdated: true,
			head: [
				{ tag: 'meta', attrs: { property: 'og:image', content: `${site}${base}/og.png` } },
				{ tag: 'meta', attrs: { property: 'og:image:alt', content: 'vinland-ui showroom: documentation rendered natively by the framework' } },
				{ tag: 'meta', attrs: { name: 'twitter:card', content: 'summary_large_image' } },
				{ tag: 'meta', attrs: { name: 'twitter:image', content: `${site}${base}/og.png` } },
				{
					tag: 'script',
					attrs: { type: 'application/ld+json' },
					content: JSON.stringify({
						'@context': 'https://schema.org',
						'@type': 'SoftwareSourceCode',
						name: 'vinland-ui',
						description: 'Utility-first UI framework for Odin',
						codeRepository: 'https://github.com/WilsonNet/vinland-ui',
						programmingLanguage: 'Odin',
						license: 'https://opensource.org/licenses/MIT',
						url: `${site}${base}/`,
					}),
				},
			],
			sidebar: groups.map((g) => ({ label: g.label, collapsed: !['Getting started', 'Core concepts'].includes(g.label), items: [{ autogenerate: { directory: g.directory } }] })),
		}),
	],
});
