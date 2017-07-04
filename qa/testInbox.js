var webdriver = require('selenium-webdriver'),
    timeStamp = ''+Math.round(+new Date()/1000),
    complexRoute = require('./complexRoute.js');
    basic = require('./basic.js');


/**
 * 0. Open Page -> login(as karpovrt);
 * 1. Create task(bychinat - executor) -> Send task;
 * 2. Check tasks(as karpovrt)(Inbox: 0, Outbox: 1, Completed: 0) -> Check tasks(as bychinat) (Inbox: 1, Outbox: 0, Completed: 0);
 * 3. Accept task(as bychinat) -> Check tasks(as bychinat)(Inbox: 0, Outbox: 0, Completed: 0) ->
 *    -> Check tasks(as kaprovrt) (Inbox: 0, Outbox: 0, Completed: 1);
 *
 * 0. Открываем страницу -> Входим в систему под karpovrt;
 * 1. Создаем задачу(bychinat - исполнитель) -> Отправляем задачу;
 * 2. Проверяем количество задач(bychinat(1; 0; 0), karpovrt(0; 1; 0))
 * 3. Исполняем задачу(за bychinat) -> Проверяем количество задач(bychinat(0; 0; 0), karpovrt(0; 0; 1));
 *
 */


basic.getDrivers().forEach(function (drv) {
    //PHASE#0: Login
    var driver = basic.getDriver(drv);
    basic.openPage(driver, drv);
    basic.login(driver, 'karpovrt', '123', '2', 'Администратор2', 0);

    //PHASE#1: Create task
    basic.openCreateDocumentForm(driver, 'Тестовый шаблон комплексного маршурута', 's-wf:ComplexRouteTest', 1);
    basic.execute(driver, "click", 'span[about="v-s:SendTask"]', "****** PHASE#1 > Create task : ERROR = Cannot click on SendTask button");
    basic.execute(driver, "click", 'div[typeof="s-wf:ComplexRouteTest"] ul[id="standard-tasks"]');
    basic.chooseFromDropdown(driver, 'v-s:hasAppointment', 'Администратор4', 'Администратор4 : Аналитик', 1);
    basic.execute(driver, "sendKeys", 'veda-control[property="rdfs:comment"] textarea[class="form-control"]',
        "****** PHASE#1 > Create task : ERROR = Cannot fill Comment field", timeStamp);
    driver.sleep(basic.FAST_OPERATION * 2);
    basic.execute(driver, "click", 'div[class="modal-dialog modal-lg"] button[id="send"]', "****** PHASE#1 > Create task : ERROR = Cannot click on Send button");
    basic.logout(driver, 1);

    //PHASE#2: Check tasks
    complexRoute.checkTasks(driver, 1, 0, 0, 'bychinat', '123', '4', 'Администратор4', 2);
    complexRoute.checkTasks(driver, 0, 1, 0, 'karpovrt', '123', '2', 'Администратор2', 2);

    //PHASE#3: Accept + Check
    complexRoute.acceptTask(driver, 0, '-', '-', 'bychinat', '123', '4', 'Администратор4', 3);
    complexRoute.checkTasks(driver, 0, 0, 1, 'bychinat', '123', '4', 'Администратор4', 3);
    complexRoute.checkTasks(driver, 0, 0, 0, 'karpovrt', '123', '2', 'Администратор2', 3);


    driver.quit();
});