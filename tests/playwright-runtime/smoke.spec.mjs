import { expect, test } from "@playwright/test";

test("runs an isolated headless browser and assertions", async ({ page, context }) => {
  await page.setContent(`
    <!doctype html>
    <html lang="zh-CN">
      <head><title>Playwright Runtime Smoke</title></head>
      <body>
        <label>用户名 <input aria-label="用户名"></label>
        <button onclick="document.querySelector('#result').textContent='提交完成'">提交</button>
        <p id="result"></p>
      </body>
    </html>
  `);

  await page.getByLabel("用户名").fill("agent-user");
  await page.getByRole("button", { name: "提交" }).click();

  await expect(page.locator("#result")).toHaveText("提交完成");
  await expect(page.getByLabel("用户名")).toHaveValue("agent-user");
  expect(await context.cookies()).toEqual([]);
});
