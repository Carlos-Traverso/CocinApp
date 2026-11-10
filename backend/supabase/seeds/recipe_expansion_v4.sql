-- Generated from frontend/src/mocks/expandedRecipes.ts. Do not edit by hand.
-- Additive only: preserves unrelated rows and user edits; refuses mismatches.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local timezone = 'UTC';

create temp table rx_recipe_source (
  id uuid primary key, source_id text not null unique, title text not null, author text not null, description text not null,
  category_label text not null, total_minutes integer not null, portions integer not null, difficulty text not null,
  symbol text not null, color text not null, featured boolean not null, cross_note text, image_path text not null, image_alt text not null,
  ingredients jsonb not null, steps jsonb not null, step_meta jsonb not null, shifts jsonb not null, dietary_keys jsonb not null
) on commit drop;
insert into rx_recipe_source values
  ('46961382-7817-596f-a598-5d3b641bf168', 'quinoa-apple-porridge', 'Porridge de quinoa y manzana', 'CocinAPP', 'Quinoa tierna cocida en agua con manzana y canela.', 'Desayuno', 30, 2, 'easy', '🥣', 'green', false, 'Para una preparación sin TACC, verificá que todos los ingredientes envasados tengan certificación sin TACC y evitá la contaminación cruzada con utensilios y superficies limpios.', '/assets/recipes/quinoa-apple-porridge.webp', 'Porridge de quinoa con cubos de manzana y canela', '[{"name":"quinoa","quantity":120,"unit":"g"},{"name":"agua","quantity":360,"unit":"ml"},{"name":"manzana","quantity":1,"unit":"u"},{"name":"canela","quantity":2,"unit":"g"}]'::jsonb, '["Enjuagá la quinoa bajo el chorro de agua en un colador fino durante 30 segundos.","Poné la quinoa y el agua en una olla; llevá a hervor y bajá el fuego.","Cociná tapado 15 minutos, hasta que absorba el agua y quede tierna.","Lavá la manzana, retirale el centro y cortala en cubos pequeños.","Incorporá manzana y canela; cociná 3 minutos más y serví tibio."]'::jsonb, '[{"durationMinutes":1,"utensils":["Colador fino"],"tip":"Enjuagar reduce el gusto amargo natural de la quinoa."},{"durationMinutes":3,"utensils":["Olla","Cuchara de madera"],"temperature":"Fuego medio hasta hervor; luego mínimo"},{"durationMinutes":15,"utensils":["Olla con tapa"],"tip":"No destapes durante la cocción para conservar el vapor."},{"durationMinutes":4,"utensils":["Cuchillo","Tabla"],"warning":"Lavá la manzana antes de cortarla."},{"durationMinutes":7,"utensils":["Olla","Cuchara"],"temperature":"Fuego bajo","tip":"Agregá un chorrito de agua si preferís una textura más cremosa."}]'::jsonb, '["Desayuno","Merienda"]'::jsonb, '["vegan","vegetarian","gluten-free","lactose-free","nut-free"]'::jsonb),
  ('d3377dd8-3907-5195-9eeb-8fa0545e751c', 'banana-rice-crepes', 'Crepes de arroz y banana', 'CocinAPP', 'Crepes suaves de harina de arroz, huevo y banana madura.', 'Desayuno', 25, 2, 'easy', '🥞', 'gold', false, 'Para una preparación sin TACC, verificá que todos los ingredientes envasados tengan certificación sin TACC y evitá la contaminación cruzada con utensilios y superficies limpios.', '/assets/recipes/banana-rice-crepes.webp', 'Crepes dorados de harina de arroz con banana', '[{"name":"harina de arroz","quantity":100,"unit":"g"},{"name":"huevos","quantity":2,"unit":"u"},{"name":"banana","quantity":1,"unit":"u"},{"name":"Aceite de oliva","quantity":10,"unit":"ml"},{"name":"agua","quantity":120,"unit":"ml"}]'::jsonb, '["Pisá la banana en un bol y mezclala con los huevos.","Sumá harina de arroz y agua de a poco; batí hasta lograr una mezcla lisa.","Calentá una sartén antiadherente y pincelala con aceite.","Verté un cucharón pequeño y girá la sartén para formar un disco fino.","Cociná 2 minutos, dalo vuelta con espátula y cociná 1 minuto más. Repetí."]'::jsonb, '[{"durationMinutes":3,"utensils":["Bol","Tenedor"],"tip":"Usá una banana bien madura para endulzar naturalmente."},{"durationMinutes":4,"utensils":["Batidor"],"tip":"Si quedan grumos, dejá reposar 5 minutos y volvé a batir."},{"durationMinutes":2,"utensils":["Sartén antiadherente","Pincel"],"temperature":"Fuego medio"},{"durationMinutes":2,"utensils":["Cucharón","Sartén"],"tip":"Una capa fina se cocina pareja y se despega mejor."},{"durationMinutes":14,"utensils":["Espátula","Sartén"],"temperature":"Fuego medio bajo","warning":"Cociná hasta que el huevo esté completamente cuajado."}]'::jsonb, '["Desayuno","Merienda"]'::jsonb, '["vegetarian","gluten-free","lactose-free","nut-free"]'::jsonb),
  ('dcec2847-c71f-5ec1-89e4-f6f442ba8f46', 'chickpea-spinach-scramble', 'Revuelto de garbanzos y espinaca', 'CocinAPP', 'Garbanzos cocidos salteados con espinaca y tomate.', 'Desayuno', 20, 2, 'easy', '🍳', 'green', false, 'Para una preparación sin TACC, verificá que todos los ingredientes envasados tengan certificación sin TACC y evitá la contaminación cruzada con utensilios y superficies limpios.', '/assets/recipes/chickpea-spinach-scramble.webp', 'Revuelto de garbanzos con espinaca y tomate', '[{"name":"garbanzos cocidos","quantity":240,"unit":"g"},{"name":"espinaca","quantity":100,"unit":"g"},{"name":"tomate","quantity":1,"unit":"u"},{"name":"Aceite de oliva","quantity":15,"unit":"ml"}]'::jsonb, '["Lavá la espinaca y el tomate; escurrí bien los garbanzos.","Cortá el tomate en cubos y picá groseramente la espinaca.","Calentá el aceite en una sartén y salteá el tomate 4 minutos.","Agregá garbanzos y espinaca; mezclá y cociná 6 minutos hasta que la espinaca se ablande y todo esté humeante.","Retirá del fuego y serví caliente."]'::jsonb, '[{"durationMinutes":3,"utensils":["Colador","Tabla"],"warning":"Lavá las verduras antes de manipularlas."},{"durationMinutes":3,"utensils":["Cuchillo","Tabla"]},{"durationMinutes":4,"utensils":["Sartén","Cuchara"],"temperature":"Fuego medio"},{"durationMinutes":6,"utensils":["Sartén","Espátula"],"temperature":"Fuego medio","tip":"Aplastá algunos garbanzos para una textura más ligada."},{"durationMinutes":4,"utensils":["Platos"],"tip":"Serví enseguida para conservar la textura."}]'::jsonb, '["Desayuno","Almuerzo"]'::jsonb, '["vegan","vegetarian","gluten-free","lactose-free","nut-free"]'::jsonb),
  ('52a38bbc-e782-5671-9756-3a77d4746630', 'ricotta-tomato-toast', 'Tostada de ricota y tomate', 'CocinAPP', 'Pan integral tostado con ricota cremosa y tomate fresco.', 'Desayuno', 12, 2, 'easy', '🍞', 'gold', false, null, '/assets/recipes/ricotta-tomato-toast.webp', 'Tostadas integrales con ricota y rodajas de tomate', '[{"name":"pan integral","quantity":4,"unit":"u"},{"name":"ricota","quantity":120,"unit":"g"},{"name":"tomate","quantity":1,"unit":"u"},{"name":"Aceite de oliva","quantity":10,"unit":"ml"}]'::jsonb, '["Lavá el tomate y cortalo en rodajas finas.","Tostá las rebanadas de pan hasta que estén doradas por fuera.","Distribuí la ricota sobre las tostadas.","Acomodá el tomate encima y terminá con un hilo de aceite de oliva.","Serví inmediatamente para que el pan conserve su textura."]'::jsonb, '[{"durationMinutes":2,"utensils":["Cuchillo","Tabla"],"warning":"Lavá el tomate antes de cortarlo."},{"durationMinutes":4,"utensils":["Tostadora o sartén"],"temperature":"Tostadora en nivel medio o sartén a fuego medio"},{"durationMinutes":2,"utensils":["Cuchara"],"tip":"Dejá la ricota unos minutos fuera de la heladera para untarla fácilmente."},{"durationMinutes":2,"utensils":["Cuchara"],"tip":"Agregá el aceite justo antes de servir."},{"durationMinutes":2,"utensils":["Platos"]}]'::jsonb, '["Desayuno","Merienda"]'::jsonb, '["vegetarian","nut-free"]'::jsonb),
  ('1b1ab323-528a-5655-a01e-1f4642a934b3', 'strawberry-chia-pudding', 'Pudín de chía y frutillas', 'CocinAPP', 'Chía hidratada en leche de soja sin gluten y frutillas frescas.', 'Desayuno', 240, 2, 'easy', '🍓', 'pink', false, 'Para una preparación sin TACC, verificá que todos los ingredientes envasados tengan certificación sin TACC y evitá la contaminación cruzada con utensilios y superficies limpios.', '/assets/recipes/strawberry-chia-pudding.webp', 'Pudín de chía con leche de soja y frutillas', '[{"name":"leche de soja sin gluten","quantity":300,"unit":"ml","category":"Almacén"},{"name":"semillas de chía","quantity":40,"unit":"g"},{"name":"frutillas","quantity":150,"unit":"g"}]'::jsonb, '["Mezclá la leche de soja con las semillas de chía en un recipiente con tapa.","Esperá 10 minutos, revolvé para distribuir las semillas y tapá.","Refrigerá al menos 3 horas y 40 minutos, hasta que espese por completo.","Lavá las frutillas, quitá los cabitos y cortalas.","Repartí el pudín en dos vasos y cubrí con frutillas."]'::jsonb, '[{"durationMinutes":2,"utensils":["Recipiente con tapa","Cuchara"],"tip":"Elegí leche de soja certificada sin gluten y sin frutos secos."},{"durationMinutes":10,"utensils":["Cuchara"],"tip":"El segundo mezclado evita que la chía forme grumos."},{"durationMinutes":220,"utensils":["Heladera"],"temperature":"Refrigeración a 5 °C o menos","tip":"El tiempo total de refrigeración indicado es de 3 horas y 40 minutos."},{"durationMinutes":4,"utensils":["Colador","Cuchillo","Tabla"],"warning":"Lavá las frutillas antes de cortarlas."},{"durationMinutes":4,"utensils":["Vasos","Cuchara"]}]'::jsonb, '["Desayuno","Merienda"]'::jsonb, '["vegan","vegetarian","gluten-free","lactose-free","nut-free"]'::jsonb),
  ('59b5a08f-3fb7-58a7-a1f1-0269f55e3b63', 'lentil-burgers', 'Hamburguesas de lentejas', 'CocinAPP', 'Medallones de lentejas cocidas, zanahoria y harina de arroz.', 'Almuerzo', 40, 4, 'easy', '🍔', 'green', false, 'Para una preparación sin TACC, verificá que todos los ingredientes envasados tengan certificación sin TACC y evitá la contaminación cruzada con utensilios y superficies limpios.', '/assets/recipes/lentil-burgers.webp', 'Hamburguesas doradas de lentejas y zanahoria', '[{"name":"lentejas cocidas","quantity":400,"unit":"g"},{"name":"harina de arroz","quantity":60,"unit":"g"},{"name":"zanahoria","quantity":1,"unit":"u"},{"name":"Aceite de oliva","quantity":20,"unit":"ml"}]'::jsonb, '["Precalentá el horno a 200 °C y cubrí una placa con papel para horno.","Rallá la zanahoria y escurrí bien las lentejas cocidas.","Pisá las lentejas con un tenedor, dejando algunos trozos enteros.","Mezclá con la zanahoria y la harina de arroz hasta obtener una pasta que se pueda moldear.","Formá cuatro medallones, acomodalos en la placa aceitada y horneá 20 minutos; dalos vuelta a mitad de cocción, hasta dorar y calentar por completo."]'::jsonb, '[{"durationMinutes":8,"utensils":["Horno","Placa","Papel para horno"],"temperature":"Precalentar a 200 °C"},{"durationMinutes":4,"utensils":["Rallador","Colador"],"warning":"Lavá la zanahoria antes de rallarla."},{"durationMinutes":4,"utensils":["Bol","Tenedor"]},{"durationMinutes":4,"utensils":["Bol","Cuchara"],"tip":"Si la mezcla está muy húmeda, añadí una cucharada extra de harina de arroz."},{"durationMinutes":20,"utensils":["Placa","Espátula","Horno"],"temperature":"200 °C","tip":"El horneado evita freír los medallones y permite que se doren de ambos lados."}]'::jsonb, '["Almuerzo","Cena"]'::jsonb, '["vegan","vegetarian","gluten-free","lactose-free","nut-free"]'::jsonb),
  ('2bbdbc9a-ee6a-578c-b1c2-05c7102fab92', 'chicken-lettuce-wraps', 'Wraps de lechuga con pollo', 'CocinAPP', 'Pollo bien cocido con arroz, zanahoria y hojas de lechuga.', 'Almuerzo', 35, 2, 'easy', '🥬', 'green', false, 'Para una preparación sin TACC, verificá que todos los ingredientes envasados tengan certificación sin TACC y evitá la contaminación cruzada con utensilios y superficies limpios.', '/assets/recipes/chicken-lettuce-wraps.webp', 'Hojas de lechuga rellenas de pollo, arroz y zanahoria', '[{"name":"pechuga de pollo","quantity":250,"unit":"g"},{"name":"arroz cocido","quantity":200,"unit":"g"},{"name":"lechuga","quantity":8,"unit":"u"},{"name":"zanahoria","quantity":1,"unit":"u"},{"name":"Aceite de oliva","quantity":10,"unit":"ml"}]'::jsonb, '["Lavá las hojas de lechuga y la zanahoria; rallá esta última.","Cortá el pollo en cubos pequeños usando tabla y cuchillo separados de los vegetales.","Calentá el aceite en una sartén y cociná el pollo 8–10 minutos, revolviendo, hasta que el centro alcance 74 °C.","Agregá arroz cocido y zanahoria; mezclá y calentá 3 minutos.","Rellená las hojas de lechuga y serví enseguida."]'::jsonb, '[{"durationMinutes":5,"utensils":["Colador","Rallador"],"warning":"Lavá las verduras y secá la lechuga con cuidado."},{"durationMinutes":3,"utensils":["Tabla exclusiva","Cuchillo"],"warning":"Lavá manos y utensilios tras manipular pollo crudo; no reutilices la tabla para alimentos listos."},{"durationMinutes":12,"utensils":["Sartén","Espátula","Termómetro"],"temperature":"Fuego medio alto; centro del pollo a 74 °C","warning":"El pollo debe alcanzar 74 °C en el centro para ser seguro."},{"durationMinutes":5,"utensils":["Sartén","Cuchara"],"temperature":"Fuego medio","tip":"Usá arroz cocido refrigerado correctamente o recién preparado."},{"durationMinutes":10,"utensils":["Cuchara"],"warning":"No dejes el relleno cocido a temperatura ambiente por más de 2 horas."}]'::jsonb, '["Almuerzo","Cena"]'::jsonb, '["gluten-free","lactose-free","nut-free"]'::jsonb),
  ('71239640-965f-5fb7-847b-f80f92c1b84e', 'tuna-stuffed-potatoes', 'Papas rellenas de atún', 'CocinAPP', 'Papas tiernas rellenas con atún y tomate fresco.', 'Almuerzo', 55, 2, 'easy', '🥔', 'gold', false, 'Para una preparación sin TACC, verificá que todos los ingredientes envasados tengan certificación sin TACC y evitá la contaminación cruzada con utensilios y superficies limpios.', '/assets/recipes/tuna-stuffed-potatoes.webp', 'Papas asadas rellenas de atún y tomate', '[{"name":"Papa","quantity":500,"unit":"g"},{"name":"atún al natural escurrido","quantity":160,"unit":"g"},{"name":"tomate","quantity":1,"unit":"u"},{"name":"Aceite de oliva","quantity":10,"unit":"ml"}]'::jsonb, '["Calentá el horno a 200 °C y lavá las papas; pinchalas varias veces con un tenedor.","Colocalas en una fuente y horneá 40 minutos, hasta que un cuchillo entre fácilmente.","Escurrí el atún y cortá el tomate lavado en cubos.","Abrí las papas a lo largo, ahuecá apenas el centro y mezclá la pulpa con el atún y el tomate.","Rellená, rociá con aceite y serví caliente."]'::jsonb, '[{"durationMinutes":5,"utensils":["Horno","Fuente","Tenedor"],"temperature":"Precalentar a 200 °C","warning":"Manipulá con cuidado la fuente caliente."},{"durationMinutes":40,"utensils":["Horno","Cuchillo"],"temperature":"200 °C","tip":"El tiempo depende del tamaño; verificá que estén tiernas."},{"durationMinutes":4,"utensils":["Abrelatas","Colador","Cuchillo","Tabla"],"warning":"Refrigerá el atún sobrante en un recipiente limpio."},{"durationMinutes":4,"utensils":["Cuchara","Bol"],"warning":"Las papas estarán muy calientes al abrirlas."},{"durationMinutes":2,"utensils":["Cuchara"],"tip":"Serví de inmediato."}]'::jsonb, '["Almuerzo","Cena"]'::jsonb, '["gluten-free","lactose-free","nut-free"]'::jsonb),
  ('d9ecc980-695a-58b2-9e0e-25c2fae5a9de', 'vegetable-polenta', 'Polenta con verduras', 'CocinAPP', 'Polenta cremosa acompañada de zucchini y tomate salteados.', 'Almuerzo', 30, 2, 'easy', '🍲', 'gold', false, 'Para una preparación sin TACC, verificá que todos los ingredientes envasados tengan certificación sin TACC y evitá la contaminación cruzada con utensilios y superficies limpios.', '/assets/recipes/vegetable-polenta.webp', 'Polenta cremosa con zucchini y salsa de tomate', '[{"name":"polenta","quantity":120,"unit":"g"},{"name":"zucchini","quantity":1,"unit":"u"},{"name":"tomate","quantity":2,"unit":"u"},{"name":"Aceite de oliva","quantity":15,"unit":"ml"},{"name":"agua","quantity":600,"unit":"ml"}]'::jsonb, '["Lavá el zucchini y los tomates; cortalos en cubos.","Calentá la mitad del aceite en una sartén y cociná las verduras 10 minutos, hasta tiernas.","En una olla llevá el agua a hervor y verté la polenta en forma de lluvia mientras revolvés.","Cociná según el envase, revolviendo hasta que espese y no queden partes secas.","Serví la polenta con las verduras y el aceite restante."]'::jsonb, '[{"durationMinutes":4,"utensils":["Cuchillo","Tabla"],"warning":"Lavá las verduras antes de cortarlas."},{"durationMinutes":10,"utensils":["Sartén","Espátula"],"temperature":"Fuego medio"},{"durationMinutes":4,"utensils":["Olla","Cuchara de madera"],"temperature":"Fuego alto hasta hervor","warning":"Verté el agua con cuidado para evitar salpicaduras."},{"durationMinutes":10,"utensils":["Batidor o cuchara"],"temperature":"Fuego bajo","tip":"Seguí el tiempo indicado por el paquete de polenta certificada."},{"durationMinutes":2,"utensils":["Platos"]}]'::jsonb, '["Almuerzo","Cena"]'::jsonb, '["vegan","vegetarian","gluten-free","lactose-free","nut-free"]'::jsonb),
  ('47011cd0-455a-561f-83e8-52b51e63cce0', 'white-bean-salad', 'Ensalada de porotos blancos', 'CocinAPP', 'Porotos, tomate y zanahoria con aderezo de limón y oliva.', 'Almuerzo', 15, 2, 'easy', '🥗', 'green', false, 'Para una preparación sin TACC, verificá que todos los ingredientes envasados tengan certificación sin TACC y evitá la contaminación cruzada con utensilios y superficies limpios.', '/assets/recipes/white-bean-salad.webp', 'Ensalada de porotos blancos con tomate, zanahoria y limón', '[{"name":"porotos blancos cocidos","quantity":300,"unit":"g"},{"name":"tomate","quantity":1,"unit":"u"},{"name":"zanahoria","quantity":1,"unit":"u"},{"name":"limón","quantity":1,"unit":"u"},{"name":"Aceite de oliva","quantity":15,"unit":"ml"}]'::jsonb, '["Escurrí y enjuagá los porotos; lavá el tomate, la zanahoria y el limón.","Cortá el tomate en cubos y rallá la zanahoria.","Mezclá el jugo de medio limón con el aceite en un bol.","Incorporá porotos, tomate y zanahoria; mezclá suavemente con el aderezo.","Dejá reposar 5 minutos en frío y serví."]'::jsonb, '[{"durationMinutes":3,"utensils":["Colador","Bol"],"warning":"Usá porotos cocidos y conservados refrigerados de forma segura."},{"durationMinutes":4,"utensils":["Cuchillo","Tabla","Rallador"],"warning":"Lavá bien los vegetales y el limón."},{"durationMinutes":2,"utensils":["Bol","Tenedor"]},{"durationMinutes":2,"utensils":["Cuchara"],"tip":"Mezclá con movimientos envolventes para mantener enteros los porotos."},{"durationMinutes":4,"utensils":["Heladera","Platos"],"temperature":"Refrigeración a 5 °C o menos","tip":"Consumí la ensalada recién preparada o mantenela refrigerada."}]'::jsonb, '["Almuerzo"]'::jsonb, '["vegan","vegetarian","gluten-free","lactose-free","nut-free"]'::jsonb),
  ('0ef28344-ee57-5759-af9b-e1e3b1dfcbce', 'baked-cinnamon-apples', 'Manzanas asadas con canela', 'CocinAPP', 'Manzanas tiernas horneadas con canela y un poco de agua.', 'Merienda', 40, 2, 'easy', '🍎', 'pink', false, 'Para una preparación sin TACC, verificá que todos los ingredientes envasados tengan certificación sin TACC y evitá la contaminación cruzada con utensilios y superficies limpios.', '/assets/recipes/baked-cinnamon-apples.webp', 'Manzanas asadas espolvoreadas con canela', '[{"name":"manzana","quantity":2,"unit":"u"},{"name":"canela","quantity":2,"unit":"g"},{"name":"agua","quantity":60,"unit":"ml"}]'::jsonb, '["Precalentá el horno a 190 °C y lavá las manzanas.","Retirá el centro con cuidado y cortá cada manzana en mitades.","Acomodá en una fuente, espolvoreá canela y agregá el agua al fondo.","Horneá 25 minutos, hasta que estén tiernas al pincharlas.","Dejá reposar 5 minutos antes de servir."]'::jsonb, '[{"durationMinutes":5,"utensils":["Horno","Fuente"],"temperature":"Precalentar a 190 °C","warning":"Mantené las manos alejadas del horno caliente."},{"durationMinutes":3,"utensils":["Cuchillo","Tabla","Cuchara parisina"],"warning":"Retirá el centro sin atravesar la base."},{"durationMinutes":2,"utensils":["Fuente","Cuchara"]},{"durationMinutes":25,"utensils":["Horno","Tenedor"],"temperature":"190 °C","warning":"Usá agarraderas para retirar la fuente caliente."},{"durationMinutes":5,"utensils":["Rejilla"],"tip":"El reposo permite que el almíbar se asiente."}]'::jsonb, '["Merienda","Desayuno"]'::jsonb, '["vegan","vegetarian","gluten-free","lactose-free","nut-free"]'::jsonb),
  ('f6602b8f-af1a-5d5e-96f7-a294ac34b95f', 'cocoa-banana-icecream', 'Helado de banana y cacao', 'CocinAPP', 'Postre helado de banana madura y cacao amargo sin azúcar.', 'Merienda', 320, 2, 'easy', '🍨', 'pink', false, 'Para una preparación sin TACC, verificá que todos los ingredientes envasados tengan certificación sin TACC y evitá la contaminación cruzada con utensilios y superficies limpios.', '/assets/recipes/cocoa-banana-icecream.webp', 'Helado cremoso de banana con cacao', '[{"name":"banana","quantity":3,"unit":"u"},{"name":"cacao amargo sin azúcar","quantity":15,"unit":"g"}]'::jsonb, '["Pelá las bananas, cortalas en rodajas y acomodalas separadas en una bandeja.","Congelá las rodajas durante 4 horas y 30 minutos, hasta que estén firmes.","Procesá las bananas congeladas con el cacao, haciendo pausas para raspar los bordes.","Continuá hasta lograr una crema homogénea y serví como helado suave.","Para una textura más firme, llevá al freezer 30 minutos adicionales antes de servir."]'::jsonb, '[{"durationMinutes":5,"utensils":["Cuchillo","Tabla","Bandeja"],"tip":"Separá las rodajas para que no se congelen en un bloque."},{"durationMinutes":270,"utensils":["Freezer"],"temperature":"Freezer a −18 °C o menos","tip":"Tiempo total de congelación de las bananas: 4 horas y 30 minutos."},{"durationMinutes":10,"utensils":["Procesadora","Espátula"],"warning":"Desenchufá la procesadora antes de retirar restos de las cuchillas."},{"durationMinutes":5,"utensils":["Cuchara"],"tip":"Serví enseguida para una consistencia tipo soft."},{"durationMinutes":30,"utensils":["Recipiente con tapa","Freezer"],"temperature":"Freezer a −18 °C o menos","tip":"Congelación opcional para una consistencia más firme."}]'::jsonb, '["Merienda"]'::jsonb, '["vegan","vegetarian","gluten-free","lactose-free","nut-free"]'::jsonb),
  ('ded76ce4-9b03-583f-b7d6-b7ad2986cc76', 'orange-rice-muffins', 'Muffins de naranja y arroz', 'CocinAPP', 'Muffins aromáticos de harina de arroz, naranja y huevo.', 'Merienda', 40, 6, 'easy', '🧁', 'gold', false, 'Para una preparación sin TACC, verificá que todos los ingredientes envasados tengan certificación sin TACC y evitá la contaminación cruzada con utensilios y superficies limpios.', '/assets/recipes/orange-rice-muffins.webp', 'Muffins dorados de harina de arroz y naranja', '[{"name":"harina de arroz","quantity":180,"unit":"g"},{"name":"naranja","quantity":1,"unit":"u"},{"name":"huevos","quantity":2,"unit":"u"},{"name":"azúcar","quantity":80,"unit":"g"},{"name":"polvo de hornear","quantity":8,"unit":"g"},{"name":"Aceite de oliva","quantity":50,"unit":"ml"}]'::jsonb, '["Precalentá el horno a 180 °C y prepará seis moldes para muffins.","Lavá la naranja, rallá finamente su cáscara y exprimí el jugo.","Batí los huevos con el azúcar; añadí aceite y jugo de naranja.","Incorporá harina de arroz y polvo de hornear hasta integrar, sin sobrebatir.","Repartí la mezcla en los moldes hasta dos tercios y horneá 20 minutos.","Verificá que un palillo salga limpio; dejá entibiar antes de desmoldar."]'::jsonb, '[{"durationMinutes":8,"utensils":["Horno","Molde para muffins"],"temperature":"Precalentar a 180 °C","tip":"Usá pirotines o aceitá moldes certificados."},{"durationMinutes":4,"utensils":["Rallador","Exprimidor"],"warning":"Lavá la naranja antes de usar su cáscara."},{"durationMinutes":4,"utensils":["Bol","Batidor"],"warning":"No uses huevos con cáscara rota."},{"durationMinutes":4,"utensils":["Espátula"],"tip":"Mezclá solo hasta que no se vea harina seca."},{"durationMinutes":20,"utensils":["Cuchara","Horno"],"temperature":"180 °C","warning":"El huevo debe quedar completamente cocido; no pruebes masa cruda."},{"durationMinutes":0,"utensils":["Palillo","Rejilla"],"warning":"Dejá enfriar antes de manipular el molde caliente."}]'::jsonb, '["Merienda","Desayuno"]'::jsonb, '["vegetarian","gluten-free","lactose-free","nut-free"]'::jsonb),
  ('bcc2f035-368a-5d8d-9dba-c3efbd51cfb3', 'hummus-carrot-sticks', 'Hummus sin tahini con bastones', 'CocinAPP', 'Pasta de garbanzos, limón y oliva servida con zanahoria cruda.', 'Merienda', 15, 2, 'easy', '🥕', 'gold', false, 'Para una preparación sin TACC, verificá que todos los ingredientes envasados tengan certificación sin TACC y evitá la contaminación cruzada con utensilios y superficies limpios.', '/assets/recipes/hummus-carrot-sticks.webp', 'Hummus de garbanzos sin tahini con bastones de zanahoria', '[{"name":"garbanzos cocidos","quantity":240,"unit":"g"},{"name":"limón","quantity":0.5,"unit":"u"},{"name":"Aceite de oliva","quantity":20,"unit":"ml"},{"name":"agua","quantity":30,"unit":"ml"},{"name":"zanahoria cruda","quantity":2,"unit":"u"}]'::jsonb, '["Escurrí los garbanzos y lavá el limón y las zanahorias.","Procesá garbanzos con jugo de medio limón, aceite y la mitad del agua.","Añadí el agua restante de a poco hasta obtener una pasta untable.","Pelá las zanahorias y cortalas en bastones del mismo largo.","Serví los bastones con el hummus."]'::jsonb, '[{"durationMinutes":3,"utensils":["Colador","Lavamanos"],"warning":"Enjuagá bien las zanahorias antes de pelarlas."},{"durationMinutes":4,"utensils":["Procesadora","Espátula"],"tip":"Esta versión no lleva tahini ni otros frutos secos."},{"durationMinutes":2,"utensils":["Procesadora"],"tip":"Ajustá con agua hasta alcanzar la textura deseada."},{"durationMinutes":4,"utensils":["Pelapapas","Cuchillo","Tabla"],"warning":"Usá tabla limpia para las verduras crudas."},{"durationMinutes":2,"utensils":["Plato"],"tip":"Mantené refrigerado el hummus que no vayas a servir."}]'::jsonb, '["Merienda"]'::jsonb, '["vegan","vegetarian","gluten-free","lactose-free","nut-free"]'::jsonb),
  ('b774a6dd-8f75-5c8a-b072-64d098ab337c', 'pear-ricotta-cup', 'Vasito de pera y ricota', 'CocinAPP', 'Pera fresca con ricota suave y canela.', 'Merienda', 10, 2, 'easy', '🍐', 'pink', false, null, '/assets/recipes/pear-ricotta-cup.webp', 'Vasito de ricota con pera y canela', '[{"name":"pera","quantity":2,"unit":"u"},{"name":"ricota","quantity":160,"unit":"g"},{"name":"canela","quantity":2,"unit":"g"}]'::jsonb, '["Lavá las peras y cortalas en cubos pequeños, retirando el centro.","Repartí la ricota en dos vasos.","Añadí los cubos de pera sobre la ricota.","Espolvoreá canela y serví frío."]'::jsonb, '[{"durationMinutes":4,"utensils":["Cuchillo","Tabla"],"warning":"Lavá las peras antes de cortarlas."},{"durationMinutes":2,"utensils":["Cuchara","Vasos"],"tip":"Usá ricota refrigerada y dentro de su fecha de consumo."},{"durationMinutes":2,"utensils":["Cuchara"]},{"durationMinutes":2,"utensils":["Cucharita"],"temperature":"Servir frío"}]'::jsonb, '["Merienda","Desayuno"]'::jsonb, '["vegetarian","nut-free"]'::jsonb),
  ('08f4c678-274e-501f-abf3-71544d359970', 'stuffed-zucchini-rice', 'Zucchinis rellenos de arroz', 'CocinAPP', 'Zucchinis al horno rellenos con arroz, tomate y cebolla.', 'Cena', 55, 2, 'easy', '🥒', 'green', false, 'Para una preparación sin TACC, verificá que todos los ingredientes envasados tengan certificación sin TACC y evitá la contaminación cruzada con utensilios y superficies limpios.', '/assets/recipes/stuffed-zucchini-rice.webp', 'Zucchinis al horno rellenos de arroz y tomate', '[{"name":"zucchini","quantity":2,"unit":"u"},{"name":"Arroz","quantity":100,"unit":"g"},{"name":"tomate","quantity":1,"unit":"u"},{"name":"cebolla","quantity":1,"unit":"u"},{"name":"Aceite de oliva","quantity":15,"unit":"ml"},{"name":"agua","quantity":200,"unit":"ml"}]'::jsonb, '["Precalentá el horno a 190 °C; lavá los zucchinis y cortalos a lo largo.","Ahuecá cada mitad con una cuchara, reservando la pulpa.","Picá cebolla, tomate y pulpa; salteá con aceite 5 minutos.","Agregá arroz seco y agua; cociná 12 minutos a fuego bajo, hasta que el arroz esté casi tierno.","Rellená los zucchinis, acomodalos en una fuente y horneá 20 minutos hasta que estén tiernos.","Serví caliente."]'::jsonb, '[{"durationMinutes":5,"utensils":["Horno","Fuente","Cuchillo"],"temperature":"Precalentar a 190 °C","warning":"Lavá los vegetales antes de cortarlos."},{"durationMinutes":5,"utensils":["Cuchara","Tabla"],"tip":"Dejá una pared de aproximadamente 5 mm para que mantengan la forma."},{"durationMinutes":8,"utensils":["Cuchillo","Tabla","Sartén"],"temperature":"Fuego medio"},{"durationMinutes":12,"utensils":["Sartén con tapa","Cuchara"],"temperature":"Fuego bajo","tip":"Si el arroz absorbe toda el agua antes de ablandar, agregá un poco más."},{"durationMinutes":20,"utensils":["Fuente","Horno"],"temperature":"190 °C","warning":"Usá agarraderas al retirar la fuente caliente."},{"durationMinutes":5,"utensils":["Platos"]}]'::jsonb, '["Cena","Almuerzo"]'::jsonb, '["vegan","vegetarian","gluten-free","lactose-free","nut-free"]'::jsonb),
  ('fa601cd1-9e6f-5e73-8666-108266c0d236', 'red-lentil-carrot-soup', 'Sopa de lentejas rojas y zanahoria', 'CocinAPP', 'Sopa sencilla de lentejas rojas con zanahoria y cebolla.', 'Cena', 40, 4, 'easy', '🍜', 'gold', false, 'Para una preparación sin TACC, verificá que todos los ingredientes envasados tengan certificación sin TACC y evitá la contaminación cruzada con utensilios y superficies limpios.', '/assets/recipes/red-lentil-carrot-soup.webp', 'Sopa espesa de lentejas rojas y zanahoria', '[{"name":"lentejas rojas secas","quantity":200,"unit":"g"},{"name":"zanahoria","quantity":2,"unit":"u"},{"name":"cebolla","quantity":1,"unit":"u"},{"name":"Aceite de oliva","quantity":15,"unit":"ml"},{"name":"agua","quantity":1000,"unit":"ml"}]'::jsonb, '["Enjuagá las lentejas en un colador y lavá la zanahoria y la cebolla.","Picá la cebolla y cortá la zanahoria en cubos pequeños.","Calentá el aceite en una olla y rehogá las verduras 5 minutos.","Sumá lentejas y agua; llevá a hervor y bajá el fuego.","Cociná destapado 20 minutos, hasta que las lentejas se desarmen y la zanahoria esté tierna.","Probá la textura, apagá el fuego y serví caliente."]'::jsonb, '[{"durationMinutes":4,"utensils":["Colador","Cuchillo"],"warning":"Lavá las verduras antes de prepararlas."},{"durationMinutes":5,"utensils":["Cuchillo","Tabla"]},{"durationMinutes":5,"utensils":["Olla","Cuchara"],"temperature":"Fuego medio"},{"durationMinutes":3,"utensils":["Olla"],"temperature":"Fuego alto hasta hervor","warning":"Evitá salpicaduras al incorporar agua."},{"durationMinutes":20,"utensils":["Olla","Cuchara"],"temperature":"Fuego bajo","tip":"Revolvé ocasionalmente para evitar que se pegue."},{"durationMinutes":3,"utensils":["Cucharón"],"tip":"Si quedó muy espesa, agregá agua caliente."}]'::jsonb, '["Cena","Almuerzo"]'::jsonb, '["vegan","vegetarian","gluten-free","lactose-free","nut-free"]'::jsonb),
  ('2aa2855c-2e28-5b6b-be21-fdf907126077', 'chicken-pumpkin-traybake', 'Pollo al horno con calabaza', 'CocinAPP', 'Pollo y calabaza asados en una fuente con cebolla.', 'Cena', 65, 4, 'easy', '🍗', 'gold', false, 'Para una preparación sin TACC, verificá que todos los ingredientes envasados tengan certificación sin TACC y evitá la contaminación cruzada con utensilios y superficies limpios.', '/assets/recipes/chicken-pumpkin-traybake.webp', 'Pollo asado con calabaza y cebolla en bandeja', '[{"name":"Pechuga de pollo","quantity":600,"unit":"g"},{"name":"calabaza","quantity":500,"unit":"g"},{"name":"cebolla","quantity":1,"unit":"u"},{"name":"Aceite de oliva","quantity":20,"unit":"ml"}]'::jsonb, '["Precalentá el horno a 200 °C; pelá la calabaza y lavá la cebolla.","Cortá calabaza y cebolla en trozos parejos.","Colocá las verduras en una fuente y mezclalas con la mitad del aceite.","Acomodá el pollo crudo encima y pincelalo con el resto del aceite usando utensilio exclusivo.","Horneá 40 minutos, hasta que el centro del pollo alcance 74 °C y la calabaza esté tierna.","Dejá reposar 5 minutos y serví."]'::jsonb, '[{"durationMinutes":8,"utensils":["Horno","Pelapapas"],"temperature":"Precalentar a 200 °C","warning":"Lavá la cebolla y evitá lavar el pollo crudo para no dispersar bacterias."},{"durationMinutes":6,"utensils":["Cuchillo","Tabla para vegetales"],"tip":"Cortá piezas similares para que se cocinen al mismo tiempo."},{"durationMinutes":3,"utensils":["Fuente","Cuchara"],"temperature":"Horno a 200 °C"},{"durationMinutes":3,"utensils":["Pinza","Pincel"],"warning":"Separá utensilios para pollo crudo y verduras listas."},{"durationMinutes":40,"utensils":["Horno","Termómetro"],"temperature":"200 °C; centro del pollo a 74 °C","warning":"Verificá 74 °C en la parte más gruesa sin tocar el hueso."},{"durationMinutes":5,"utensils":["Fuente","Platos"],"warning":"Refrigerá sobrantes dentro de las 2 horas."}]'::jsonb, '["Cena","Almuerzo"]'::jsonb, '["gluten-free","lactose-free","nut-free"]'::jsonb),
  ('719d0715-8bf3-55a0-9873-348eda693652', 'spinach-potato-frittata', 'Frittata de espinaca y papa', 'CocinAPP', 'Tortilla al horno con papa tierna, espinaca y huevo.', 'Cena', 48, 4, 'easy', '🍳', 'green', false, 'Para una preparación sin TACC, verificá que todos los ingredientes envasados tengan certificación sin TACC y evitá la contaminación cruzada con utensilios y superficies limpios.', '/assets/recipes/spinach-potato-frittata.webp', 'Frittata dorada de espinaca y papa cortada en porciones', '[{"name":"huevos","quantity":5,"unit":"u"},{"name":"espinaca","quantity":120,"unit":"g"},{"name":"Papa","quantity":200,"unit":"g"},{"name":"Aceite de oliva","quantity":15,"unit":"ml"}]'::jsonb, '["Precalentá el horno a 180 °C; lavá la papa y la espinaca.","Cortá la papa en cubos pequeños y hervila 10 minutos hasta que esté casi tierna; escurrí.","Salteá la espinaca con la mitad del aceite durante 2 minutos.","Batí los huevos en un bol e incorporá papa y espinaca.","Verté en una sartén apta para horno aceitada y cociná 20 minutos, hasta que el centro esté firme.","Dejá reposar 3 minutos y cortá en porciones."]'::jsonb, '[{"durationMinutes":5,"utensils":["Horno","Colador"],"temperature":"Precalentar a 180 °C","warning":"Lavá la espinaca cuidadosamente."},{"durationMinutes":13,"utensils":["Cuchillo","Tabla","Olla","Colador"],"temperature":"Hervor suave","tip":"Cortá cubos pequeños para acortar la cocción."},{"durationMinutes":3,"utensils":["Sartén","Espátula"],"temperature":"Fuego medio","warning":"Escurrí bien la espinaca para evitar exceso de líquido."},{"durationMinutes":4,"utensils":["Bol","Batidor"],"warning":"Mantené los huevos refrigerados y descartá los que tengan la cáscara rota."},{"durationMinutes":20,"utensils":["Sartén apta para horno","Horno"],"temperature":"180 °C","warning":"El huevo debe quedar completamente firme y cocido en el centro."},{"durationMinutes":3,"utensils":["Cuchillo","Espátula"],"warning":"Usá protección para retirar la sartén caliente."}]'::jsonb, '["Cena","Almuerzo"]'::jsonb, '["vegetarian","gluten-free","lactose-free","nut-free"]'::jsonb),
  ('456ccf4e-8bc0-5876-84a1-fbfbfa85fa19', 'fish-tomato-stew', 'Guiso de pescado y tomate', 'CocinAPP', 'Pescado cocido en una salsa suave de tomate, cebolla y papa.', 'Cena', 45, 2, 'easy', '🐟', 'blue', false, 'Para una preparación sin TACC, verificá que todos los ingredientes envasados tengan certificación sin TACC y evitá la contaminación cruzada con utensilios y superficies limpios.', '/assets/recipes/fish-tomato-stew.webp', 'Guiso de pescado con tomate, cebolla y papa', '[{"name":"Filet de pescado","quantity":300,"unit":"g"},{"name":"tomate","quantity":2,"unit":"u"},{"name":"cebolla","quantity":1,"unit":"u"},{"name":"Papa","quantity":200,"unit":"g"},{"name":"Aceite de oliva","quantity":15,"unit":"ml"},{"name":"agua","quantity":250,"unit":"ml"}]'::jsonb, '["Lavá el tomate, la papa y la cebolla; cortá todo en cubos pequeños.","Calentá el aceite en una olla y cociná la cebolla 4 minutos.","Agregá tomate, papa y agua; tapá y cociná 15 minutos, hasta que la papa esté casi tierna.","Añadí el pescado en trozos grandes, tapá y cociná 8–10 minutos, hasta que esté opaco y alcance 63 °C en el centro.","Apagá el fuego y dejá reposar 2 minutos antes de servir con cuidado."]'::jsonb, '[{"durationMinutes":6,"utensils":["Cuchillo","Tabla para vegetales"],"warning":"Lavá los vegetales antes de cortarlos."},{"durationMinutes":4,"utensils":["Olla","Cuchara"],"temperature":"Fuego medio"},{"durationMinutes":15,"utensils":["Olla con tapa"],"temperature":"Fuego medio bajo","tip":"Cortá la papa pequeña para que se cocine en el tiempo indicado."},{"durationMinutes":10,"utensils":["Tabla separada","Pinza","Termómetro"],"temperature":"Fuego bajo; centro del pescado a 63 °C","warning":"Mantené pescado crudo separado de otros alimentos; cociná hasta 63 °C o hasta que se desmenuce fácilmente."},{"durationMinutes":3,"utensils":["Cucharón"],"warning":"Retirá espinas visibles y serví caliente."}]'::jsonb, '["Cena","Almuerzo"]'::jsonb, '["gluten-free","lactose-free","nut-free"]'::jsonb);

lock table public.categorias,public.unidades,public.ingredientes,public.etiquetas_dieteticas,public.recetas,
  public.ingredientes_receta,public.pasos_receta,public.ingredientes_paso_receta,public.turnos_comida_receta,
  public.etiquetas_dieteticas_receta,public.registro_auditoria in share row exclusive mode;

create temp table rx_needed_categories(id uuid not null, legacy_id text not null, name text not null, normalized_name text primary key) on commit drop;
insert into rx_needed_categories values
  ('4c98140f-cc0c-50e8-985a-1b898c3c2f63', 'recipe-expansion-v4:category:almacen', 'Almacén', 'almacen'),
  ('307ea271-15cd-5b9c-9dec-d556971af3f5', 'recipe-expansion-v4:category:carnes y pescados', 'Carnes y pescados', 'carnes y pescados'),
  ('856d6007-82a4-5e4c-86ce-5a16dfe3387a', 'recipe-expansion-v4:category:frutas y verduras', 'Frutas y verduras', 'frutas y verduras'),
  ('577bc6c0-7718-5e61-82bf-fc66fa3a6e1f', 'recipe-expansion-v4:category:granos y legumbres', 'Granos y legumbres', 'granos y legumbres'),
  ('39100945-42e3-55b8-8504-cb9f45cba8bf', 'recipe-expansion-v4:category:huevos', 'Huevos', 'huevos'),
  ('3ef2a801-6d20-5bb3-946f-f02860e120f6', 'recipe-expansion-v4:category:lacteos', 'Lácteos', 'lacteos');
create temp table rx_needed_units(id uuid not null, abbreviation text primary key, name text not null, normalized_name text not null, dimension text not null) on commit drop;
insert into rx_needed_units values
  ('5b4725c6-74c6-5eb5-9231-712a79042782', 'g', 'Gramo', 'gramo', 'mass'),
  ('c94feebf-09f0-5cc4-944a-9e42e6d33805', 'ml', 'Mililitro', 'mililitro', 'volume'),
  ('9293f346-0d5f-5364-bc8b-42405f0c8743', 'u', 'Unidad', 'unidad', 'count');
create temp table rx_needed_ingredients(id uuid not null, legacy_id text not null, name text not null, normalized_name text primary key, category_name text not null, base_abbreviation text not null) on commit drop;
insert into rx_needed_ingredients values
  ('d0fcaa7e-9b75-5aa5-82c7-b3be7e4fa96f', 'recipe-expansion-v4:ingredient:aceite de oliva', 'Aceite de oliva', 'aceite de oliva', 'Almacén', 'ml'),
  ('13b4b042-71a6-53c0-b0be-8d961d2151ae', 'recipe-expansion-v4:ingredient:agua', 'agua', 'agua', 'Almacén', 'ml'),
  ('dfb46791-1a8e-500c-b430-a8c26ee0b5d8', 'recipe-expansion-v4:ingredient:arroz', 'Arroz', 'arroz', 'Granos y legumbres', 'g'),
  ('16fed8d3-b126-5366-a543-fee40674cb4c', 'recipe-expansion-v4:ingredient:arroz cocido', 'arroz cocido', 'arroz cocido', 'Granos y legumbres', 'g'),
  ('1d71ed9f-5379-5491-8625-2312cf67113b', 'recipe-expansion-v4:ingredient:atun al natural escurrido', 'atún al natural escurrido', 'atun al natural escurrido', 'Carnes y pescados', 'g'),
  ('152f9121-e638-587f-bc48-f1225c956f6e', 'recipe-expansion-v4:ingredient:azucar', 'azúcar', 'azucar', 'Almacén', 'g'),
  ('2374d461-bed1-5d4c-8532-5963e4a422e7', 'recipe-expansion-v4:ingredient:banana', 'banana', 'banana', 'Frutas y verduras', 'u'),
  ('5a354741-337c-5252-9c3d-c0494a18dbf2', 'recipe-expansion-v4:ingredient:cacao amargo sin azucar', 'cacao amargo sin azúcar', 'cacao amargo sin azucar', 'Almacén', 'g'),
  ('4ba75605-2967-5e31-b4df-61c404d118b1', 'recipe-expansion-v4:ingredient:calabaza', 'calabaza', 'calabaza', 'Frutas y verduras', 'g'),
  ('36418516-fa56-5657-a3d1-bc8568aa41a2', 'recipe-expansion-v4:ingredient:canela', 'canela', 'canela', 'Almacén', 'g'),
  ('ada9a02c-ecd3-58e0-a0fd-adc92d052b1b', 'recipe-expansion-v4:ingredient:cebolla', 'cebolla', 'cebolla', 'Frutas y verduras', 'u'),
  ('288b3e53-da28-5365-8ed8-f48c8bb3c037', 'recipe-expansion-v4:ingredient:espinaca', 'espinaca', 'espinaca', 'Frutas y verduras', 'g'),
  ('3ae298c6-65cd-58f4-9d32-851c5e43ae76', 'recipe-expansion-v4:ingredient:filet de pescado', 'Filet de pescado', 'filet de pescado', 'Carnes y pescados', 'g'),
  ('e81f812d-b848-5f6f-a186-e3363c6048f3', 'recipe-expansion-v4:ingredient:frutillas', 'frutillas', 'frutillas', 'Frutas y verduras', 'g'),
  ('7dc05a48-5eba-5277-973f-85286f2f54a3', 'recipe-expansion-v4:ingredient:garbanzos cocidos', 'garbanzos cocidos', 'garbanzos cocidos', 'Granos y legumbres', 'g'),
  ('5356c915-32b2-5e47-8314-6a81d2b197a6', 'recipe-expansion-v4:ingredient:harina de arroz', 'harina de arroz', 'harina de arroz', 'Granos y legumbres', 'g'),
  ('36befcc1-ab7a-55f2-afd8-d7db61e24749', 'recipe-expansion-v4:ingredient:huevos', 'huevos', 'huevos', 'Huevos', 'u'),
  ('c7039e7d-4524-553d-be5b-cafe19f11735', 'recipe-expansion-v4:ingredient:leche de soja sin gluten', 'leche de soja sin gluten', 'leche de soja sin gluten', 'Almacén', 'ml'),
  ('ae23c386-5f40-5562-aa25-cfbdf9602bb2', 'recipe-expansion-v4:ingredient:lechuga', 'lechuga', 'lechuga', 'Frutas y verduras', 'u'),
  ('042a3698-314b-5322-a759-bfc01be8741c', 'recipe-expansion-v4:ingredient:lentejas cocidas', 'lentejas cocidas', 'lentejas cocidas', 'Granos y legumbres', 'g'),
  ('242ec616-33ad-58e2-9f47-2fca1313a1e4', 'recipe-expansion-v4:ingredient:lentejas rojas secas', 'lentejas rojas secas', 'lentejas rojas secas', 'Granos y legumbres', 'g'),
  ('bb7cbf29-6e90-5335-886f-4037ff35437d', 'recipe-expansion-v4:ingredient:limon', 'limón', 'limon', 'Frutas y verduras', 'u'),
  ('9e0ae516-3a36-5572-aefb-bddb4f35005b', 'recipe-expansion-v4:ingredient:manzana', 'manzana', 'manzana', 'Frutas y verduras', 'u'),
  ('ccd1e7c1-1c5c-5c79-8148-ac904b7d88b9', 'recipe-expansion-v4:ingredient:naranja', 'naranja', 'naranja', 'Frutas y verduras', 'u'),
  ('74872b35-22c7-5592-9160-d44efbc17b08', 'recipe-expansion-v4:ingredient:pan integral', 'pan integral', 'pan integral', 'Almacén', 'u'),
  ('ddfa9d7a-9ec1-56ae-acf1-1b1fc1d1dfd3', 'recipe-expansion-v4:ingredient:papa', 'Papa', 'papa', 'Frutas y verduras', 'g'),
  ('977fca08-791b-5349-8d6c-edd983f6a8c8', 'recipe-expansion-v4:ingredient:pechuga de pollo', 'pechuga de pollo', 'pechuga de pollo', 'Carnes y pescados', 'g'),
  ('1576f48b-a692-5483-8b48-7e677a23d5c8', 'recipe-expansion-v4:ingredient:pera', 'pera', 'pera', 'Frutas y verduras', 'u'),
  ('aca892ec-71a4-5f22-8faa-2b617f23af1f', 'recipe-expansion-v4:ingredient:polenta', 'polenta', 'polenta', 'Granos y legumbres', 'g'),
  ('4234c590-dfc0-584e-83d9-a68c5931002b', 'recipe-expansion-v4:ingredient:polvo de hornear', 'polvo de hornear', 'polvo de hornear', 'Almacén', 'g'),
  ('b5016906-8cfa-5ab5-9612-b1062247b04e', 'recipe-expansion-v4:ingredient:porotos blancos cocidos', 'porotos blancos cocidos', 'porotos blancos cocidos', 'Granos y legumbres', 'g'),
  ('95398e74-9a42-5a36-b87b-c01fd1e821f8', 'recipe-expansion-v4:ingredient:quinoa', 'quinoa', 'quinoa', 'Granos y legumbres', 'g'),
  ('62970e49-df5d-5bf7-8bd4-3c76f9d26c27', 'recipe-expansion-v4:ingredient:ricota', 'ricota', 'ricota', 'Lácteos', 'g'),
  ('6507c868-f4f5-5c91-9340-4dc7eb07577e', 'recipe-expansion-v4:ingredient:semillas de chia', 'semillas de chía', 'semillas de chia', 'Almacén', 'g'),
  ('44636f7f-3a21-579f-8633-f444c629480c', 'recipe-expansion-v4:ingredient:tomate', 'tomate', 'tomate', 'Frutas y verduras', 'u'),
  ('3a081012-4468-5597-b285-7e3992c34558', 'recipe-expansion-v4:ingredient:zanahoria', 'zanahoria', 'zanahoria', 'Frutas y verduras', 'u'),
  ('92e87087-e4e7-57c5-84c3-27fa19c16997', 'recipe-expansion-v4:ingredient:zanahoria cruda', 'zanahoria cruda', 'zanahoria cruda', 'Frutas y verduras', 'u'),
  ('81b21e82-4133-5380-bf99-295ad71b2ea8', 'recipe-expansion-v4:ingredient:zucchini', 'zucchini', 'zucchini', 'Frutas y verduras', 'u');
create temp table rx_tag_input(tag_key text primary key, label text not null) on commit drop;
insert into rx_tag_input values
  ('gluten-free', 'Sin TACC'),
  ('vegetarian', 'Vegetariana'),
  ('vegan', 'Vegana'),
  ('lactose-free', 'Sin lactosa'),
  ('nut-free', 'Sin frutos secos');

create temp table rx_category_map on commit drop as
select n.normalized_name, n.name, n.legacy_id, coalesce(c.id,n.id) id, c.id is null as needs_insert
from rx_needed_categories n left join public.categorias c
  on c.normalized_name=n.normalized_name and not c.is_deleted;
create temp table rx_unit_map on commit drop as
select n.abbreviation, n.name, n.normalized_name, n.dimension, coalesce(u.id,n.id) id, u.id is null as needs_insert
from rx_needed_units n left join public.unidades u on lower(u.abbreviation)=lower(n.abbreviation);
create temp table rx_ingredient_map on commit drop as
select n.normalized_name,n.name,n.legacy_id,n.category_name,n.base_abbreviation,
  coalesce(i.id,n.id) id,i.id is null as needs_insert,coalesce(existing_category.active and not existing_category.is_deleted,true) category_active
from rx_needed_ingredients n
left join public.ingredientes i on i.normalized_name=n.normalized_name
left join public.categorias existing_category on existing_category.id=i.category_id;

do $$
declare problems text;
begin
  if to_regclass('public.recetas') is null or to_regclass('public.ingredientes_receta') is null
    or to_regclass('public.pasos_receta') is null or to_regclass('public.ingredientes_paso_receta') is null
    or to_regclass('public.turnos_comida_receta') is null or to_regclass('public.etiquetas_dieteticas_receta') is null
    or to_regclass('public.estado_escritura_receta_admin') is null then
    raise exception 'Falta el esquema relacional final, los renombres españoles o el estado de escritura de recetas. No se modificó nada.';
  end if;
  if (select count(*) from rx_recipe_source) <> 20 then raise exception 'El lote debe contener exactamente 20 recetas.'; end if;

  select string_agg(problem, E'
') into problems from (
    select 'Categoría ausente/ambigua/inactiva: '||n.name problem from rx_needed_categories n
      where (select count(*) from public.categorias c where c.normalized_name=n.normalized_name and not c.is_deleted and c.active) > 1
        or exists(select 1 from public.categorias c where c.normalized_name=n.normalized_name and not c.is_deleted and not c.active)
        or exists(select 1 from public.categorias c where c.id=n.id and (c.normalized_name is distinct from n.normalized_name or c.is_deleted))
        or exists(select 1 from public.categorias c where c.legacy_id=n.legacy_id and (c.normalized_name is distinct from n.normalized_name or c.is_deleted))
    union all
    select 'Unidad ausente/ambigua/inactiva o con dimensión distinta: '||n.abbreviation from rx_needed_units n
      where (select count(*) from public.unidades u where lower(u.abbreviation)=lower(n.abbreviation)) > 1
        or exists(select 1 from public.unidades u where lower(u.abbreviation)=lower(n.abbreviation) and (not u.active or u.is_deleted or u.dimension<>n.dimension or u.base_unit_id is not null))
        or exists(select 1 from public.unidades u where u.id=n.id and lower(u.abbreviation)<>lower(n.abbreviation))
        or exists(select 1 from public.unidades u where u.legacy_id='recipe-expansion-v4:unit:'||n.abbreviation and lower(u.abbreviation)<>lower(n.abbreviation))
        or exists(select 1 from public.unidades u where u.normalized_name=n.normalized_name and not u.is_deleted and lower(u.abbreviation)<>lower(n.abbreviation))
    union all
    select 'Ingrediente duplicado/inactivo/ID en conflicto: '||n.name from rx_needed_ingredients n
      where (select count(*) from public.ingredientes i where i.normalized_name=n.normalized_name) > 1
        or exists(select 1 from public.ingredientes i where i.normalized_name=n.normalized_name and (not i.active or i.is_deleted))
        or exists(select 1 from public.ingredientes i where i.id=n.id and i.normalized_name is distinct from n.normalized_name)
        or exists(select 1 from public.ingredientes i where i.legacy_id=n.legacy_id and i.normalized_name is distinct from n.normalized_name)
        or exists(select 1 from public.ingredientes i join public.categorias c on c.id=i.category_id
          where i.normalized_name=n.normalized_name and (not c.active or c.is_deleted
            or c.normalized_name<>(select normalized_name from rx_needed_categories where name=n.category_name)))
    union all
    select 'Categoría de ingrediente inexistente/inactiva: '||n.name from rx_needed_ingredients n
      where not exists(select 1 from rx_category_map c where c.normalized_name=(select normalized_name from rx_needed_categories where name=n.category_name) and c.id is not null)
    union all
    select 'Unidad base faltante: '||n.base_abbreviation from rx_needed_ingredients n
      where not exists(select 1 from rx_unit_map u where u.abbreviation=n.base_abbreviation)
    union all
    select 'Dimensión/unidad base incompatible: '||n.name from rx_needed_ingredients n
      join rx_unit_map expected on expected.abbreviation=n.base_abbreviation
      left join public.ingredientes i on i.normalized_name=n.normalized_name
      left join public.unidades base on base.id=i.base_unit_id
      where i.id is not null and (base.id is null or base.dimension<>expected.dimension or base.base_unit_id is not null)
    union all
    select 'Etiqueta dietaria ausente/inactiva: '||tag.label from rx_tag_input tag
      where not exists(select 1 from public.etiquetas_dieteticas d where d.tag_key=tag.tag_key and d.active)
    union all
    select 'Colisión de id/legacy_id/título: '||r.title from rx_recipe_source r
      where exists(select 1 from public.recetas x where x.id=r.id and (x.legacy_id is distinct from r.source_id or x.recipe_source<>'official' or x.owner_user_id is not null))
        or exists(select 1 from public.recetas x where x.legacy_id=r.source_id and x.id<>r.id)
        or exists(select 1 from public.recetas x where x.id<>r.id and x.recipe_source='official' and x.owner_user_id is null and not x.is_deleted
          and lower(regexp_replace(regexp_replace(normalize(trim(x.title),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g'))
            = lower(regexp_replace(regexp_replace(normalize(trim(r.title),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g')))
  ) issues;
  if problems is not null then raise exception 'Preflight bloqueado; corregir referencias/colisiones antes de importar:%', E'
'||problems; end if;
end;
$$;

create temp table rx_categories_to_insert on commit drop as
select c.* from rx_category_map c where c.needs_insert
  and exists(select 1 from rx_needed_ingredients i where i.category_name=c.name
    and not exists(select 1 from public.ingredientes known where known.normalized_name=i.normalized_name));
create temp table rx_units_to_insert on commit drop as select * from rx_unit_map where needs_insert;
create temp table rx_ingredients_to_insert on commit drop as select * from rx_ingredient_map where needs_insert;

-- Add only catalog references that are genuinely missing. Never reactivate or overwrite a row.
insert into public.categorias(id,legacy_id,name,normalized_name,active,is_deleted,version)
select id,legacy_id,name,normalized_name,true,false,1 from rx_categories_to_insert;
insert into public.unidades(id,legacy_id,name,normalized_name,abbreviation,dimension,base_unit_id,equivalence_multiplier,active,is_deleted,version)
select id,'recipe-expansion-v4:unit:'||abbreviation,name,normalized_name,abbreviation,dimension,null,null,true,false,1
from rx_units_to_insert;
insert into public.ingredientes(id,legacy_id,name,normalized_name,category_id,base_unit_id,active,is_deleted,version)
select m.id,m.legacy_id,m.name,m.normalized_name,c.id,u.id,true,false,1
from rx_ingredients_to_insert m join rx_category_map c on c.normalized_name=(select normalized_name from rx_needed_categories where name=m.category_name)
join rx_unit_map u on u.abbreviation=m.base_abbreviation;

create temp table rx_expected_ingredients on commit drop as
select r.id recipe_id, line.n::integer position, m.id ingredient_id, (line.value->>'quantity')::numeric quantity,
  u.id unit_id, coalesce(line.value->>'note','') note, line.value->>'name' source_name, line.value->>'unit' source_unit
from rx_recipe_source r cross join lateral jsonb_array_elements(r.ingredients) with ordinality line(value,n)
join rx_ingredient_map m on m.normalized_name=lower(regexp_replace(regexp_replace(normalize(trim(line.value->>'name'),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g'))
join rx_unit_map u on lower(u.abbreviation)=lower(line.value->>'unit');
do $$
begin
  if exists(select 1 from rx_expected_ingredients e join rx_ingredient_map m on m.id=e.ingredient_id
    join rx_unit_map recipe_unit on recipe_unit.id=e.unit_id
    where (m.needs_insert and recipe_unit.id<>(select id from rx_unit_map where abbreviation=m.base_abbreviation))
      or (not m.needs_insert and exists(select 1 from public.ingredientes i join public.unidades ingredient_base on ingredient_base.id=i.base_unit_id
        where i.id=m.id and recipe_unit.id<>ingredient_base.id))) then
    raise exception 'Unidad de receta incompatible con la unidad base del ingrediente. Se revierte la transacción.';
  end if;
end;
$$;
create temp table rx_expected_steps on commit drop as
select r.id recipe_id, step.n::integer position, step.value #>> '{}' instruction,
  coalesce((meta.value->>'durationMinutes')::integer,(meta.value->>'minutes')::integer) duration_minutes,
  nullif(meta.value->>'temperature','') temperature,nullif(meta.value->>'tip','') tip,nullif(meta.value->>'warning','') warning,
  coalesce(array(select jsonb_array_elements_text(coalesce(meta.value->'utensils','[]'::jsonb))),'{}') utensils,
  nullif(meta.value->>'specialInstructions','') special_instructions,coalesce(meta.value->'stepIngredients','[]'::jsonb) step_ingredients
from rx_recipe_source r cross join lateral jsonb_array_elements(r.steps) with ordinality step(value,n)
left join lateral (select r.step_meta->(step.n::integer-1) value) meta on true;
create temp table rx_expected_step_links on commit drop as
select s.recipe_id,s.position step_position,ri.position ingredient_position,(item.value->>'quantity')::numeric quantity_override
from rx_expected_steps s cross join lateral jsonb_array_elements(s.step_ingredients) item(value)
join rx_expected_ingredients ri on ri.recipe_id=s.recipe_id
  and lower(regexp_replace(regexp_replace(normalize(trim(item.value->>'name'),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g'))
      = lower(regexp_replace(regexp_replace(normalize(trim(ri.source_name),NFD),U&'[\0300-\036f]','','g'),'\s+',' ','g'))
  and lower(item.value->>'unit')=lower(ri.source_unit);
create temp table rx_expected_shifts on commit drop as
select distinct r.id recipe_id,case shift.value #>> '{}' when 'Desayuno' then 'breakfast' when 'Almuerzo' then 'lunch' when 'Merienda' then 'snack' when 'Cena' then 'dinner' end meal_shift
from rx_recipe_source r cross join lateral jsonb_array_elements(r.shifts) shift(value);
create temp table rx_expected_tags on commit drop as
select distinct r.id recipe_id,tag.value #>> '{}' tag_key
from rx_recipe_source r cross join lateral jsonb_array_elements(r.dietary_keys) tag(value);

create temp table rx_recipes_to_insert on commit drop as
select r.* from rx_recipe_source r where not exists(select 1 from public.recetas x where x.id=r.id);

do $$
declare problems text;
begin
  select string_agg(problem,E'
') into problems from (
    select 'Ingrediente/unidad no resuelta o incompatible: '||r.title||' / '||(line.value->>'name') problem
    from rx_recipe_source r cross join lateral jsonb_array_elements(r.ingredients) with ordinality line(value,ordinality)
    where (select count(*) from rx_expected_ingredients i where i.recipe_id=r.id and i.position=line.ordinality::integer)<>1
    union all
    select 'Etiqueta dietaria sin destino activo: '||r.title||' / '||(tag.value #>> '{}') from rx_recipe_source r
      cross join lateral jsonb_array_elements(r.dietary_keys) tag(value)
      where not exists(select 1 from rx_expected_tags t join public.etiquetas_dieteticas d on d.tag_key=t.tag_key and d.active where t.recipe_id=r.id and t.tag_key=tag.value #>> '{}')
    union all
    select 'Metadato de paso sin ingrediente inequívoco: '||r.title||' / paso '||s.position from rx_expected_steps s
      join rx_recipe_source r on r.id=s.recipe_id
      where jsonb_array_length(s.step_ingredients)<>(select count(*) from rx_expected_step_links l where l.recipe_id=s.recipe_id and l.step_position=s.position)
  ) unresolved;
  if problems is not null then raise exception 'Preflight bloqueado; faltan asociaciones:%', E'
'||problems; end if;

  -- Exact rows are skipped on rerun. Any same-ID/legacy-ID row with different data fails closed.
  if exists(
    select 1 from rx_recipe_source e join public.recetas r on r.id=e.id or r.legacy_id=e.source_id
    where r.id is distinct from e.id or r.legacy_id is distinct from e.source_id or r.recipe_source<>'official' or r.owner_user_id is not null
      or r.title is distinct from e.title or r.author is distinct from e.author or r.description is distinct from e.description
      or r.category_label is distinct from e.category_label or r.total_minutes is distinct from e.total_minutes or r.portions is distinct from e.portions
      or r.difficulty is distinct from e.difficulty or r.calories_per_portion is not null or r.preparation_minutes is not null or r.cooking_minutes is not null
      or r.publication_status is distinct from 'published' or not r.active or r.is_deleted or r.featured is distinct from e.featured
      or r.symbol is distinct from e.symbol or r.color is distinct from e.color or r.cross_contamination_note is distinct from e.cross_note
      or r.image_path is distinct from e.image_path or r.image_alt is distinct from e.image_alt or r.version is distinct from 1
  ) then raise exception 'La receta existente coincide por id/legacy_id pero no con este seed. Se aborta sin sobrescribirla.'; end if;

  if exists(
    (select e.recipe_id,e.position,e.ingredient_id,e.quantity,e.unit_id,e.note from rx_expected_ingredients e
      join rx_recipe_source r on r.id=e.recipe_id join public.recetas x on x.id=r.id)
    except
    (select a.recipe_id,a.position,a.ingredient_id,a.quantity,a.unit_id,a.note from public.ingredientes_receta a join rx_recipe_source r on r.id=a.recipe_id)
  ) or exists(
    (select a.recipe_id,a.position,a.ingredient_id,a.quantity,a.unit_id,a.note from public.ingredientes_receta a join rx_recipe_source r on r.id=a.recipe_id)
    except
    (select e.recipe_id,e.position,e.ingredient_id,e.quantity,e.unit_id,e.note from rx_expected_ingredients e join rx_recipe_source r on r.id=e.recipe_id join public.recetas x on x.id=r.id)
  ) then raise exception 'Las líneas de ingredientes de una receta existente difieren del seed. No se sobrescribe.'; end if;
  if exists(
    (select e.recipe_id,e.position,e.instruction,e.duration_minutes,e.temperature,e.tip,e.warning,e.utensils,e.special_instructions from rx_expected_steps e join rx_recipe_source r on r.id=e.recipe_id join public.recetas x on x.id=r.id)
    except
    (select a.recipe_id,a.position,a.instruction,a.duration_minutes,a.temperature,a.tip,a.warning,a.utensils,a.special_instructions from public.pasos_receta a join rx_recipe_source r on r.id=a.recipe_id)
  ) or exists(
    (select a.recipe_id,a.position,a.instruction,a.duration_minutes,a.temperature,a.tip,a.warning,a.utensils,a.special_instructions from public.pasos_receta a join rx_recipe_source r on r.id=a.recipe_id)
    except
    (select e.recipe_id,e.position,e.instruction,e.duration_minutes,e.temperature,e.tip,e.warning,e.utensils,e.special_instructions from rx_expected_steps e join rx_recipe_source r on r.id=e.recipe_id join public.recetas x on x.id=r.id)
  ) then raise exception 'Los pasos de una receta existente difieren del seed. No se sobrescribe.'; end if;
  if exists(
    (select e.recipe_id,e.step_position,e.ingredient_position,e.quantity_override from rx_expected_step_links e join rx_recipe_source r on r.id=e.recipe_id join public.recetas x on x.id=r.id)
    except
    (select s.recipe_id,s.position,ri.position,link.quantity_override from public.ingredientes_paso_receta link join public.pasos_receta s on s.id=link.step_id join public.ingredientes_receta ri on ri.id=link.recipe_ingredient_id join rx_recipe_source r on r.id=s.recipe_id)
  ) or exists(
    (select s.recipe_id,s.position,ri.position,link.quantity_override from public.ingredientes_paso_receta link join public.pasos_receta s on s.id=link.step_id join public.ingredientes_receta ri on ri.id=link.recipe_ingredient_id join rx_recipe_source r on r.id=s.recipe_id)
    except
    (select e.recipe_id,e.step_position,e.ingredient_position,e.quantity_override from rx_expected_step_links e join rx_recipe_source r on r.id=e.recipe_id join public.recetas x on x.id=r.id)
  ) then raise exception 'Las referencias de ingredientes por paso difieren del seed. No se sobrescribe.'; end if;
  if exists(
    (select e.recipe_id,e.meal_shift from rx_expected_shifts e join rx_recipe_source r on r.id=e.recipe_id join public.recetas x on x.id=r.id)
    except
    (select a.recipe_id,a.meal_shift from public.turnos_comida_receta a join rx_recipe_source r on r.id=a.recipe_id)
  ) or exists(
    (select a.recipe_id,a.meal_shift from public.turnos_comida_receta a join rx_recipe_source r on r.id=a.recipe_id)
    except
    (select e.recipe_id,e.meal_shift from rx_expected_shifts e join rx_recipe_source r on r.id=e.recipe_id join public.recetas x on x.id=r.id)
  ) then raise exception 'Los turnos de comida de una receta existente difieren del seed. No se sobrescribe.'; end if;
  if exists(
    (select e.recipe_id,d.id from rx_expected_tags e join rx_recipe_source r on r.id=e.recipe_id join public.recetas x on x.id=r.id join public.etiquetas_dieteticas d on d.tag_key=e.tag_key)
    except
    (select a.recipe_id,a.dietary_tag_id from public.etiquetas_dieteticas_receta a join rx_recipe_source r on r.id=a.recipe_id)
  ) or exists(
    (select a.recipe_id,a.dietary_tag_id from public.etiquetas_dieteticas_receta a join rx_recipe_source r on r.id=a.recipe_id)
    except
    (select e.recipe_id,d.id from rx_expected_tags e join rx_recipe_source r on r.id=e.recipe_id join public.recetas x on x.id=r.id join public.etiquetas_dieteticas d on d.tag_key=e.tag_key)
  ) then raise exception 'Las etiquetas de una receta existente difieren del seed. No se sobrescribe.'; end if;
end;
$$;

-- Insert recipes not already present. Their deterministic IDs and legacy slugs keep routes stable.
insert into public.recetas(id,legacy_id,owner_user_id,recipe_source,title,author,description,category_label,total_minutes,preparation_minutes,cooking_minutes,
  portions,difficulty,calories_per_portion,publication_status,active,is_deleted,featured,symbol,color,cross_contamination_note,image_path,image_alt,version)
select r.id,r.source_id,null,'official',r.title,r.author,r.description,r.category_label,r.total_minutes,null,null,r.portions,r.difficulty,null,
  'published',true,false,r.featured,r.symbol,r.color,r.cross_note,r.image_path,r.image_alt,1
from rx_recipes_to_insert r;
insert into public.ingredientes_receta(id,recipe_id,ingredient_id,quantity,unit_id,note,position)
select md5('recipe-expansion-v4:recipe-line:'||e.recipe_id::text||':'||e.position)::uuid,e.recipe_id,e.ingredient_id,e.quantity,e.unit_id,e.note,e.position
from rx_expected_ingredients e join rx_recipes_to_insert r on r.id=e.recipe_id;
insert into public.pasos_receta(id,recipe_id,position,instruction,duration_minutes,temperature,tip,warning,utensils,special_instructions)
select md5('recipe-expansion-v4:recipe-step:'||e.recipe_id::text||':'||e.position)::uuid,e.recipe_id,e.position,e.instruction,e.duration_minutes,e.temperature,e.tip,e.warning,e.utensils,e.special_instructions
from rx_expected_steps e join rx_recipes_to_insert r on r.id=e.recipe_id;
insert into public.ingredientes_paso_receta(step_id,recipe_ingredient_id,quantity_override)
select md5('recipe-expansion-v4:recipe-step:'||l.recipe_id::text||':'||l.step_position)::uuid,
  md5('recipe-expansion-v4:recipe-line:'||l.recipe_id::text||':'||l.ingredient_position)::uuid,l.quantity_override
from rx_expected_step_links l join rx_recipes_to_insert r on r.id=l.recipe_id;
insert into public.turnos_comida_receta(recipe_id,meal_shift)
select e.recipe_id,e.meal_shift from rx_expected_shifts e join rx_recipes_to_insert r on r.id=e.recipe_id;
insert into public.etiquetas_dieteticas_receta(recipe_id,dietary_tag_id)
select e.recipe_id,d.id from rx_expected_tags e join public.etiquetas_dieteticas d on d.tag_key=e.tag_key
join rx_recipes_to_insert r on r.id=e.recipe_id;

-- Record the operator-driven catalog additions; actor_user_id is NULL for SQL Editor execution.
insert into public.registro_auditoria(actor_user_id,action,details)
select null::uuid,'catalog.category_saved',jsonb_build_object('entity_id',c.id,'version',1,'source','recipe-expansion-v4') from rx_categories_to_insert c
union all
select null::uuid,'catalog.unit_saved',jsonb_build_object('entity_id',u.id,'version',1,'source','recipe-expansion-v4') from rx_units_to_insert u
union all
select null::uuid,'catalog.ingredient_saved',jsonb_build_object('entity_id',i.id,'version',1,'source','recipe-expansion-v4') from rx_ingredients_to_insert i
union all
select null::uuid,'catalog.recipe_saved',jsonb_build_object('entity_id',r.id,'version',1,'source','recipe-expansion-v4') from rx_recipes_to_insert r;

do $$
begin
  if exists(select 1 from rx_recipe_source r where not exists(select 1 from public.recetas x where x.id=r.id and x.legacy_id=r.source_id)) then
    raise exception 'Validación final falló: faltan recetas del lote.';
  end if;
  if exists(
    (select recipe_id,position,ingredient_id,quantity,unit_id,note from rx_expected_ingredients)
    except
    (select recipe_id,position,ingredient_id,quantity,unit_id,note from public.ingredientes_receta where recipe_id in (select id from rx_recipe_source))
  ) then raise exception 'Validación final falló: faltan ingredientes de receta.'; end if;
  if exists(
    (select recipe_id,position,instruction,duration_minutes,temperature,tip,warning,utensils,special_instructions from rx_expected_steps)
    except
    (select recipe_id,position,instruction,duration_minutes,temperature,tip,warning,utensils,special_instructions from public.pasos_receta where recipe_id in (select id from rx_recipe_source))
  ) then raise exception 'Validación final falló: faltan pasos o metadatos.'; end if;
  if exists(
    (select recipe_id,step_position,ingredient_position,quantity_override from rx_expected_step_links)
    except
    (select s.recipe_id,s.position,ri.position,l.quantity_override from public.ingredientes_paso_receta l
      join public.pasos_receta s on s.id=l.step_id join public.ingredientes_receta ri on ri.id=l.recipe_ingredient_id
      where s.recipe_id in (select id from rx_recipe_source))
  ) then raise exception 'Validación final falló: faltan referencias de ingrediente por paso.'; end if;
  if exists(
    (select recipe_id,meal_shift from rx_expected_shifts)
    except
    (select recipe_id,meal_shift from public.turnos_comida_receta where recipe_id in (select id from rx_recipe_source))
  ) then raise exception 'Validación final falló: faltan turnos de comida.'; end if;
  if exists(
    (select e.recipe_id,d.id from rx_expected_tags e join public.etiquetas_dieteticas d on d.tag_key=e.tag_key)
    except
    (select recipe_id,dietary_tag_id from public.etiquetas_dieteticas_receta where recipe_id in (select id from rx_recipe_source))
  ) then raise exception 'Validación final falló: faltan etiquetas dietarias.'; end if;
end;
$$;

select 'PASS: preflight, referencias y contenido de las 20 recetas verificados' as validation;
select 'recipes_inserted' as result,count(*) from rx_recipes_to_insert
union all select 'ingredients_inserted',count(*) from rx_ingredients_to_insert
union all select 'categories_inserted',count(*) from rx_categories_to_insert
union all select 'units_inserted',count(*) from rx_units_to_insert;

commit;
