import type { OxfmtConfig } from "oxfmt";
import { defineConfig } from "oxfmt";

const config: OxfmtConfig = defineConfig({
    printWidth: 120,
    tabWidth: 4,
    useTabs: false,
    overrides: [
        {
            files: ["*.json"],
            options: {
                printWidth: 80,
                trailingComma: "none",
            },
        },
        {
            files: ["*.md", "*.yaml", "*.yml"],
            options: {
                tabWidth: 2,
            },
        },
    ],
});

export default config;
